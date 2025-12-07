defmodule Core.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for HH.ru API calls.

  HH.ru limits: ~200 applications/day
  Configuration:
  - capacity: 20 tokens
  - refill_rate: 8 tokens per hour (192/day, leaving buffer)
  """
  use GenServer
  require Logger

  @capacity 20
  @refill_rate 8
  @refill_interval 3_600_000  # 1 hour in milliseconds

  defmodule State do
    @moduledoc false
    defstruct [:buckets]
  end

  defmodule Bucket do
    @moduledoc false
    defstruct tokens: 20,
              capacity: 20,
              refill_rate: 8,
              last_refill: nil
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if action is allowed for given user_id and action_type.
  Returns {:ok, remaining} or {:error, :rate_limited}
  """
  def check_rate_limit(user_id, action_type \\ :application) do
    GenServer.call(__MODULE__, {:check_limit, user_id, action_type})
  end

  @doc """
  Get current rate limit status for user
  """
  def get_status(user_id, action_type \\ :application) do
    GenServer.call(__MODULE__, {:get_status, user_id, action_type})
  end

  @doc """
  Reset rate limit for user (admin function)
  """
  def reset_limit(user_id, action_type \\ :application) do
    GenServer.cast(__MODULE__, {:reset, user_id, action_type})
  end

  @doc """
  Check available tokens for a user.
  Returns {:ok, tokens} with current token count.
  """
  def check_tokens(user_id, action_type \\ :application) do
    status = get_status(user_id, action_type)
    {:ok, status.tokens}
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule periodic refill
    schedule_refill()
    {:ok, %State{buckets: %{}}}
  end

  @impl true
  def handle_call({:check_limit, user_id, action_type}, _from, state) do
    key = {user_id, action_type}
    bucket = Map.get(state.buckets, key, new_bucket())

    # Refill if needed
    bucket = maybe_refill(bucket)

    case bucket.tokens do
      tokens when tokens > 0 ->
        new_bucket = %{bucket | tokens: tokens - 1}
        new_state = %{state | buckets: Map.put(state.buckets, key, new_bucket)}
        {:reply, {:ok, new_bucket.tokens}, new_state}

      _ ->
        # Calculate when tokens will be available
        next_refill = calculate_next_refill(bucket)
        Logger.warning("Rate limit exceeded for user #{user_id}, action: #{action_type}")
        {:reply, {:error, :rate_limited, next_refill}, state}
    end
  end

  @impl true
  def handle_call({:get_status, user_id, action_type}, _from, state) do
    key = {user_id, action_type}
    bucket = Map.get(state.buckets, key, new_bucket())
    bucket = maybe_refill(bucket)

    status = %{
      tokens: bucket.tokens,
      capacity: bucket.capacity,
      refill_rate: bucket.refill_rate,
      last_refill: bucket.last_refill
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast({:reset, user_id, action_type}, state) do
    key = {user_id, action_type}
    new_state = %{state | buckets: Map.delete(state.buckets, key)}
    Logger.info("Reset rate limit for user #{user_id}, action: #{action_type}")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:refill, state) do
    # Refill all buckets
    new_buckets =
      state.buckets
      |> Enum.map(fn {key, bucket} -> {key, maybe_refill(bucket)} end)
      |> Enum.into(%{})

    # Clean up old inactive buckets (no activity in 24 hours)
    cutoff = System.system_time(:second) - 86_400
    cleaned_buckets =
      Enum.filter(new_buckets, fn {_key, bucket} ->
        bucket.last_refill && bucket.last_refill > cutoff
      end)
      |> Enum.into(%{})

    schedule_refill()
    {:noreply, %{state | buckets: cleaned_buckets}}
  end

  # Private Functions

  defp new_bucket do
    %Bucket{
      tokens: @capacity,
      capacity: @capacity,
      refill_rate: @refill_rate,
      last_refill: System.system_time(:second)
    }
  end

  defp maybe_refill(bucket) do
    now = System.system_time(:second)
    last_refill = bucket.last_refill || now
    time_since_refill = now - last_refill

    # Refill based on time passed (one refill per hour)
    hours_passed = div(time_since_refill, 3600)

    if hours_passed > 0 do
      tokens_to_add = min(hours_passed * @refill_rate, @capacity - bucket.tokens)
      new_tokens = min(bucket.tokens + tokens_to_add, @capacity)

      %{bucket |
        tokens: new_tokens,
        last_refill: now
      }
    else
      bucket
    end
  end

  defp calculate_next_refill(bucket) do
    now = System.system_time(:second)
    last_refill = bucket.last_refill || now
    seconds_until_refill = 3600 - rem(now - last_refill, 3600)
    now + seconds_until_refill
  end

  defp schedule_refill do
    Process.send_after(self(), :refill, @refill_interval)
  end
end
