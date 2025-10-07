defmodule Dashboard.Jobs.Fether do
  use GenServer
  require Logger

  @hh_api_url "https://api.hh.ru/vacancies"
  @fetch_interval 5_000

  def start_link() do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def fetch_jobs_now() do
    GenServer.cast(__MODULE__, :fetch_jobs)
  end

  def get_stats do
    GenServer.cast(__MODULE__, :get_stats)
  end

  def init(state) do
    Logger.info("Job Fetcher Started")

    Process.send_after(self(), :fetch_jobs, 1_000)

    initial_state = %{}

    {:ok, initial_state}
  end

  def handle_info(:fetch_jobs, state) do
    Logger.info("Fetching jobs concurrently")
    start_time = System.monotonic_time(:milliseconds)

    searches = %{
      %{text: "Elixir", area: 1},
      %{text: "Phoenix", area: 2},
      %{text: "Backend Developer", area: 1},
      %{text: "Full Stack", area: 1},
      %{text: "DevOps", area: 1}
    }
  end
end
