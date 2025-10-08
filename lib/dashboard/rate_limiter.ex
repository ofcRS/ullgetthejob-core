defmodule Dashboard.RateLimiter do
  @moduledoc """
  Token bucket rate limiter implementation using GenServer.

  The token bucket algorithm allows burst traffic while maintaining
  a steady average rate. Tokens are added to the bucket at a fixed rate,
  and each request consumes one or more tokens.
  """
  use GenServer
  require Logger

  @default_capacity 10
  @default_refill_rate 2
  @refill_interval 1000

  defmodule State do
    @moduledoc false
    defstruct [
      :capacity,
      :tokens,
      :refill_rate,
      :refill_interval,
      :last_refill,
      requests_allowed: 0,
      requests_denied: 0
    ]
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if a request can proceed. Returns {:ok, tokens_remaining} or {:error, :rate_limited}.
  """
  def check_rate(cost \\ 1) do
    GenServer.call(__MODULE__, {:check_rate, cost})
  end

  @doc """
  Gets current rate limiter statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Resets the rate limiter to initial state.
  """
  def reset do
    GenServer.cast(__MODULE__, :reset)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    capacity = Keyword.get(opts, :capacity, @default_capacity)
    refill_rate = Keyword.get(opts, :refill_rate, @default_refill_rate)
    refill_interval = Keyword.get(opts, :refill_interval, @refill_interval)

    state = %State{
      capacity: capacity,
      tokens: capacity,
      refill_rate: refill_rate,
      refill_interval: refill_interval,
      last_refill: System.monotonic_time(:millisecond)
    }

    # Schedule periodic token refills
    schedule_refill(refill_interval)

    Logger.info(
      "Rate Limiter started - capacity: #{capacity}, refill_rate: #{refill_rate}/#{refill_interval}ms"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:check_rate, cost}, _from, state) do
    # Refill tokens based on elapsed time
    state = refill_tokens(state)

    if state.tokens >= cost do
      new_state = %{
        state
        | tokens: state.tokens - cost,
          requests_allowed: state.requests_allowed + 1
      }

      {:reply, {:ok, new_state.tokens}, new_state}
    else
      new_state = %{state | requests_denied: state.requests_denied + 1}
      {:reply, {:error, :rate_limited}, new_state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      tokens: state.tokens,
      capacity: state.capacity,
      refill_rate: state.refill_rate,
      requests_allowed: state.requests_allowed,
      requests_denied: state.requests_denied,
      utilization: calculate_utilization(state)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast(:reset, state) do
    new_state = %{
      state
      | tokens: state.capacity,
        requests_allowed: 0,
        requests_denied: 0,
        last_refill: System.monotonic_time(:millisecond)
    }

    Logger.info("Rate limiter reset")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:refill, state) do
    state = refill_tokens(state)
    schedule_refill(state.refill_interval)
    {:noreply, state}
  end

  # Private Functions

  defp refill_tokens(state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - state.last_refill

    # Calculate how many tokens to add based on elapsed time
    tokens_to_add = div(elapsed, state.refill_interval) * state.refill_rate

    if tokens_to_add > 0 do
      new_tokens = min(state.tokens + tokens_to_add, state.capacity)

      %{
        state
        | tokens: new_tokens,
          last_refill: now
      }
    else
      state
    end
  end

  defp schedule_refill(interval) do
    Process.send_after(self(), :refill, interval)
  end

  defp calculate_utilization(state) do
    if state.capacity > 0 do
      Float.round((state.capacity - state.tokens) / state.capacity * 100, 1)
    else
      0
    end
  end
end
