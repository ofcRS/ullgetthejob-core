defmodule Core.Broadcaster do
  @moduledoc """
  Broadcasts job updates to the API service via HTTP POST
  """

  require Logger

  @api_base_url System.get_env("API_BASE_URL", "http://localhost:3000")
  @api_secret System.get_env("API_SECRET", "dev_api_secret")

  def broadcast_jobs(jobs, stats \\ %{}) do
    url = "#{@api_base_url}/api/v1/jobs/broadcast"

    body = %{
      jobs: jobs,
      stats: stats
    }

    headers = [
      {"X-Core-Secret", @api_secret}
    ]

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"ok" => true, "delivered" => count}} ->
            Logger.info("Successfully broadcast #{count} jobs")
            {:ok, count}
          _ ->
            Logger.error("Unexpected response from API: #{response_body}")
            {:error, :unexpected_response}
        end

      {:ok, %{status: status, body: response_body}} ->
        Logger.error("API returned status #{status}: #{response_body}")
        {:error, status}

      {:error, exception} ->
        Logger.error("Failed to broadcast jobs: #{inspect(exception)}")
        {:error, exception}
    end
  end

  def broadcast_dummy_jobs do
    dummy_jobs = [
      %{
        id: "dummy-1",
        title: "Senior Elixir Developer",
        company: "Tech Corp",
        area: "Moscow",
        salary: "200000-300000 RUB"
      },
      %{
        id: "dummy-2",
        title: "Full Stack Developer",
        company: "Startup Inc",
        area: "Saint Petersburg",
        salary: "150000-250000 RUB"
      }
    ]

    broadcast_jobs(dummy_jobs, %{source: "dummy"})
  end
end
