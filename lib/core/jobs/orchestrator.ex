defmodule Core.Jobs.Orchestrator do
  @moduledoc """
  Job fetching orchestrator that:
  - Periodically fetches jobs from HH.ru API
  - Broadcasts new jobs to the API service via WebSocket
  - Manages job search schedules per user
  - Handles rate limiting and retries
  """
  use GenServer
  require Logger

  alias Core.HH.Client
  alias Core.Broadcaster
  alias Core.Jobs.Enrichment

  @fetch_interval 1_800_000  # 30 minutes
  @max_jobs_per_fetch 100

  defmodule State do
    @moduledoc false
    defstruct [:schedules, :last_fetch]
  end

  defmodule Schedule do
    @moduledoc false
    defstruct [:user_id, :search_params, :enabled, :last_run, :interval]
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Schedule periodic job fetching for a user
  """
  def schedule_job_fetch(user_id, search_params, interval \\ @fetch_interval) do
    GenServer.call(__MODULE__, {:schedule, user_id, search_params, interval})
  end

  @doc """
  Unschedule job fetching for a user
  """
  def unschedule_job_fetch(user_id) do
    GenServer.cast(__MODULE__, {:unschedule, user_id})
  end

  @doc """
  Manually trigger job fetch for a user
  """
  def fetch_jobs_now(user_id) do
    GenServer.call(__MODULE__, {:fetch_now, user_id}, 30_000)
  end

  @doc """
  Fetch jobs with search params (one-time fetch)
  """
  def fetch_jobs(search_params) do
    GenServer.call(__MODULE__, {:fetch, search_params}, 30_000)
  end

  @doc """
  Get active schedules
  """
  def get_schedules do
    GenServer.call(__MODULE__, :get_schedules)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule periodic check for job fetching
    schedule_tick()

    state = %State{
      schedules: %{},
      last_fetch: nil
    }

    Logger.info("Jobs Orchestrator started")
    {:ok, state}
  end

  @impl true
  def handle_call({:schedule, user_id, search_params, interval}, _from, state) do
    schedule = %Schedule{
      user_id: user_id,
      search_params: search_params,
      enabled: true,
      last_run: nil,
      interval: interval
    }

    new_schedules = Map.put(state.schedules, user_id, schedule)
    new_state = %{state | schedules: new_schedules}

    Logger.info("Scheduled job fetch for user #{user_id}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:fetch_now, user_id}, _from, state) do
    case Map.get(state.schedules, user_id) do
      nil ->
        {:reply, {:error, :no_schedule}, state}

      schedule ->
        result = perform_fetch(schedule.search_params)

        # Only update last_run if fetch AND broadcast both succeeded
        new_schedules =
          case result do
            {:ok, _result_map} ->
              # Success - update last_run
              updated_schedule = %{schedule | last_run: System.system_time(:second)}
              Map.put(state.schedules, user_id, updated_schedule)

            {:error, _reason} ->
              # Failure - don't update last_run so retry happens sooner
              state.schedules
          end

        new_state = %{state | schedules: new_schedules}
        {:reply, result, new_state}
    end
  end

  @impl true
  def handle_call({:fetch, search_params}, _from, state) do
    result = perform_fetch(search_params)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_schedules, _from, state) do
    schedules = Map.values(state.schedules)
    {:reply, schedules, state}
  end

  @impl true
  def handle_cast({:unschedule, user_id}, state) do
    new_schedules = Map.delete(state.schedules, user_id)
    Logger.info("Unscheduled job fetch for user #{user_id}")
    {:noreply, %{state | schedules: new_schedules}}
  end

  @impl true
  def handle_info(:tick, state) do
    # Check all schedules and run if needed
    now = System.system_time(:second)

    updated_schedules =
      Enum.reduce(state.schedules, state.schedules, fn {user_id, schedule}, acc ->
        should_run =
          schedule.enabled and
          (schedule.last_run == nil or
           now - schedule.last_run >= div(schedule.interval, 1000))

        if should_run do
          Logger.info("Running scheduled fetch for user #{user_id}")

          case perform_fetch(schedule.search_params) do
            {:ok, result} ->
              # Only update last_run if both fetch AND broadcast succeeded
              fetched = Map.get(result, :fetched, 0)
              broadcast = Map.get(result, :broadcast, 0)
              Logger.info("Scheduled fetch completed for user #{user_id}: fetched=#{fetched} broadcast=#{broadcast}")
              updated = %{schedule | last_run: now}
              Map.put(acc, user_id, updated)

            {:error, {:broadcast_failed, reason}} ->
              # Broadcast failed but fetch succeeded - don't update last_run
              # so we retry sooner
              Logger.error("Scheduled fetch broadcast failed for user #{user_id}: #{inspect(reason)}")
              Logger.warning("Will retry fetch for user #{user_id} on next tick (broadcast failure)")
              acc

            {:error, {:fetch_failed, reason}} ->
              # Fetch failed - don't update last_run so we retry sooner
              Logger.error("Scheduled fetch failed for user #{user_id}: #{inspect(reason)}")
              acc

            {:error, reason} ->
              Logger.error("Scheduled fetch failed for user #{user_id}: #{inspect(reason)}")
              acc
          end
        else
          acc
        end
      end)

    schedule_tick()
    {:noreply, %{state | schedules: updated_schedules, last_fetch: now}}
  end

  # Private Functions

  defp perform_fetch(search_params) do
    Logger.info("Fetching jobs with params: #{inspect(search_params)}")

    case Client.fetch_vacancies(search_params) do
      {:ok, jobs} ->
        job_count = length(jobs)
        Logger.info("Fetched #{job_count} jobs from HH.ru")

        # Limit to prevent overwhelming the system
        jobs_to_broadcast = Enum.take(jobs, @max_jobs_per_fetch)

        # Enrich with full details before broadcasting
        enriched_jobs = Enrichment.enrich_jobs(jobs_to_broadcast)

        # Broadcast to API service
        stats = %{
          total: job_count,
          broadcasted: length(enriched_jobs),
          source: "hh.ru",
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        case Broadcaster.broadcast_jobs(enriched_jobs, stats) do
          {:ok, delivered} ->
            Logger.info("Successfully broadcast #{delivered} jobs")
            # FIXED: Return success with both fetch and broadcast counts
            {:ok, %{fetched: job_count, broadcast: delivered}}

          {:error, reason} ->
            Logger.error("Failed to broadcast jobs: #{inspect(reason)}")
            # FIXED: Return error tuple so orchestrator knows broadcast failed
            # This prevents marking the fetch as successful when users didn't receive jobs
            {:error, {:broadcast_failed, reason}}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch jobs: #{inspect(reason)}")
        {:error, {:fetch_failed, reason}}
    end
  end

  defp schedule_tick do
    # Check every 5 minutes
    Process.send_after(self(), :tick, 300_000)
  end
end
