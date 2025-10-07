defmodule Dashboard.Jobs.Fetcher do
  use GenServer
  require Logger

  @hh_api_url "https://api.hh.ru/vacancies"
  @fetch_interval 5_000

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def fetch_jobs_now() do
    GenServer.cast(__MODULE__, :fetch_jobs)
  end

  def get_stats do
    GenServer.cast(__MODULE__, :get_stats)
  end

  def init(_state) do
    Logger.info("Job Fetcher Started")

    Process.send_after(self(), :fetch_jobs, 1_000)

    initial_state = %{
      total_fetched: 0,
      fetch_count: 0,
      last_fetch_time: nil,
      errors: 0,
      current_rps: 0
    }

    {:ok, initial_state}
  end

  def handle_info(:fetch_jobs, state) do
    Logger.info("Fetching jobs concurrently")
    start_time = System.monotonic_time(:millisecond)

    searches = [
      %{text: "Elixir", area: 1},
      %{text: "Phoenix", area: 2},
      %{text: "Backend Developer", area: 1},
      %{text: "Full Stack", area: 1},
      %{text: "DevOps", area: 1}
    ]

    tasks =
      Enum.map(searches, fn search ->
        Task.async(fn -> fetch_from_api(search) end)
      end)

    results = Task.await_many(tasks, 10_0000)

    jobs =
      results
      |> Enum.flat_map(fn
        {:ok, jobs} -> jobs
        _ -> []
      end)
      |> Enum.uniq_by(& &1.id)

    Logger.info(jobs)

    # Calculate stats
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    rps = if duration > 0, do: length(jobs) * 1000 / duration, else: 0

    Phoenix.PubSub.broadcast(
      Dashboard.PubSub,
      "jobs:stream",
      {:new_jobs, jobs, %{rps: Float.round(rps, 2), duration: duration}}
    )

    new_state = %{
      state
      | total_fetched: state.total_fetched + length(jobs),
        fetch_count: state.fetch_count + 1,
        last_fetch_time: System.monotonic_time(),
        current_rps: Float.round(rps, 2)
    }

    {:noreply, new_state}
  end

  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end

  def handle_cast(:fetch_jobs, state) do
    send(self(), :fetch_jobs)
    {:noreply, state}
  end

  defp fetch_from_api(search) do
    headers = [
      {"User-Agent",
       "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    ]

    query = URI.encode_query(Map.merge(search, %{per_page: 20}))
    url = "#{@hh_api_url}?#{query}"

    case HTTPoison.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case JSON.decode(body) do
          {:ok, %{"items" => items}} ->
            jobs = Enum.map(items, &parse_job/1)
            {:ok, jobs}

          _ ->
            {:error, :parse_error}
        end

      {:ok, %{status_code: 429}} ->
        Logger.warning("RATE LIMITED!!!!")
        {:error, :rate_limited}

      error ->
        Logger.error("Fetch error: #{inspect(error)}")
        {:error, :fetch_failed}
    end
  end

  defp parse_job(item) do
    %{
      id: item["id"],
      title: item["name"],
      company: get_in(item, ["employer", "name"]),
      salary: parse_salary(item["salary"]),
      area: get_in(item, ["area", "name"]),
      created_at: item["created_at"],
      url: item["alternate_url"]
    }
  end

  defp parse_salary(nil), do: "Not specified"

  defp parse_salary(salary) do
    from = salary["from"]
    to = salary["to"]
    currency = salary["currency"]

    case {from, to} do
      {nil, nil} -> "Not specified"
      {from, nil} -> "From #{from} #{currency}"
      {nil, to} -> "Up to #{to} #{currency}"
      {from, to} -> "#{from} - #{to} #{currency}"
    end
  end

  defp parse_jobs() do
    %{}
  end
end
