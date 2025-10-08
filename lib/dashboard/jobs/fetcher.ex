defmodule Dashboard.Jobs.Fetcher do
  use GenServer
  require Logger

  alias Dashboard.RateLimiter
  alias Dashboard.Jobs

  @hh_api_url "https://api.hh.ru/vacancies"

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def fetch_jobs_now do
    GenServer.cast(__MODULE__, :fetch_jobs)
  end

  def get_stats do
    GenServer.cast(__MODULE__, :get_stats)
  end

  def init(_state) do
    Logger.info("Job Fetcher Started")

    initial_state = %{
      total_fetched: 0,
      fetch_count: 0,
      last_fetch_time: nil,
      errors: 0,
      current_rps: 0,
      search_pages: %{},
      rate_limited_count: 0
    }

    {:ok, initial_state}
  end

  def handle_info(:fetch_jobs, state) do
    # Check rate limiter before proceeding
    case RateLimiter.check_rate(5) do
      {:ok, _tokens_remaining} ->
        Logger.info("Fetching jobs concurrently")
        start_time = System.monotonic_time(:millisecond)

        searches = [
          %{text: "Elixir", area: 1},
          %{text: "Phoenix", area: 2},
          %{text: "Backend Developer", area: 1},
          %{text: "Full Stack", area: 1},
          %{text: "DevOps", area: 1}
        ]

        # Get current page for each search and prepare tasks
        task_data =
          searches
          |> Enum.map(fn search ->
            search_key = search_key(search)
            current_page = Map.get(state.search_pages, search_key, 0)

            task = Task.async(fn -> fetch_from_api(search, current_page) end)
            {task, search_key, search.text}
          end)

        {tasks, search_keys, search_queries} =
          task_data
          |> Enum.reduce({[], [], []}, fn {task, key, query}, {tasks, keys, queries} ->
            {[task | tasks], [key | keys], [query | queries]}
          end)
          |> then(fn {tasks, keys, queries} ->
            {Enum.reverse(tasks), Enum.reverse(keys), Enum.reverse(queries)}
          end)

        results = Task.await_many(tasks, 10_0000)

        # Combine results with search queries
        jobs =
          results
          |> Enum.zip(search_queries)
          |> Enum.flat_map(fn
            {{:ok, jobs}, search_query} ->
              Enum.map(jobs, fn job -> Map.put(job, :search_query, search_query) end)

            _ ->
              []
          end)
          |> Enum.uniq_by(& &1.id)

        Logger.info("Fetched #{length(jobs)} jobs")

        # Save jobs to database
        if length(jobs) > 0 do
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          db_jobs =
            Enum.map(jobs, fn job ->
              %{
                external_id: job.id,
                title: job.title,
                company: job.company,
                salary: job.salary,
                area: job.area,
                url: job.url,
                source: "hh.ru",
                search_query: job.search_query,
                fetched_at: now
              }
            end)

          {:ok, count} = Jobs.bulk_upsert_jobs(db_jobs)
          Logger.info("Saved #{count} jobs to database")
        end

        # Calculate stats
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        rps = if duration > 0, do: length(jobs) * 1000 / duration, else: 0

        Phoenix.PubSub.broadcast(
          Dashboard.PubSub,
          "jobs:stream",
          {:new_jobs, jobs, %{rps: Float.round(rps, 2), duration: duration}}
        )

        # Update pagination - increment page for each search
        # Reset to 0 if we reach page 99 (hh.ru max is 100 pages, 0-99)
        updated_pages =
          Enum.reduce(search_keys, state.search_pages, fn key, pages ->
            current_page = Map.get(pages, key, 0)
            next_page = if current_page >= 99, do: 0, else: current_page + 1
            Map.put(pages, key, next_page)
          end)

        new_state = %{
          state
          | total_fetched: state.total_fetched + length(jobs),
            fetch_count: state.fetch_count + 1,
            last_fetch_time: System.monotonic_time(),
            current_rps: Float.round(rps, 2),
            search_pages: updated_pages
        }

        {:noreply, new_state}

      {:error, :rate_limited} ->
        Logger.warning("Rate limited - skipping fetch")

        new_state = %{
          state
          | rate_limited_count: state.rate_limited_count + 1
        }

        {:noreply, new_state}
    end
  end

  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end

  def handle_cast(:fetch_jobs, state) do
    send(self(), :fetch_jobs)
    {:noreply, state}
  end

  defp search_key(search) do
    "#{search.text}_#{search.area}"
  end

  defp fetch_from_api(search, page) do
    headers = [
      {"User-Agent",
       "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    ]

    query = URI.encode_query(Map.merge(search, %{per_page: 20, page: page}))
    url = "#{@hh_api_url}?#{query}"

    Logger.info("Fetching #{search.text} (area: #{search.area}) page #{page}")

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"items" => items}}} ->
        jobs = Enum.map(items, &parse_job/1)
        {:ok, jobs}

      {:ok, %{status: 429}} ->
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
end
