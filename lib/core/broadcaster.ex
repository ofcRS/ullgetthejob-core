defmodule Core.Broadcaster do
  @moduledoc """
  Broadcasts job updates to the API service via HTTP POST and
  real-time updates via WebSocket/PubSub
  """

  require Logger
  alias Phoenix.PubSub

  @api_base_url System.get_env("API_BASE_URL", "http://localhost:3000")
  @api_secret System.get_env("ORCHESTRATOR_SECRET", "shared_secret_between_core_and_api")
  @pubsub Core.PubSub

  def broadcast_jobs(jobs, stats \\ %{}) do
    url = "#{@api_base_url}/api/v1/jobs/broadcast"

    enriched_jobs =
      Enum.map(jobs, fn job ->
        %{
          id: Map.get(job, :hh_vacancy_id) || Map.get(job, "hh_vacancy_id") || Map.get(job, :id) || Map.get(job, "id"),
          title: Map.get(job, :title) || Map.get(job, "title"),
          company: Map.get(job, :company) || Map.get(job, "company"),
          salary: Map.get(job, :salary) || Map.get(job, "salary"),
          area: Map.get(job, :area) || Map.get(job, "area"),
          url: Map.get(job, :url) || Map.get(job, "url"),
          skills: Map.get(job, :skills) || Map.get(job, "skills") || [],
          description: Map.get(job, :description) || Map.get(job, "description"),
          has_test: Map.get(job, :has_test) || Map.get(job, "has_test") || false
        }
      end)

    body = %{
      jobs: enriched_jobs,
      stats: stats
    }

    headers = [
      {"X-Core-Secret", @api_secret},
      {"Content-Type", "application/json"}
    ]

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        resp_map =
          case response_body do
            %{} = map -> map
            bin when is_binary(bin) -> case Jason.decode(bin) do
              {:ok, map} -> map
              _ -> %{}
            end
            _ -> %{}
          end

        case resp_map do
          %{"ok" => true, "delivered" => count} ->
            Logger.info("Successfully broadcast #{count} jobs")
            {:ok, count}
          _ ->
            Logger.error("Unexpected response from API: #{inspect(response_body)}")
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

  @doc """
  Broadcast customization progress via PubSub
  """
  def broadcast_customization_progress(user_id, data) do
    message = %{
      type: "customization_progress",
      data: data,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    PubSub.broadcast(@pubsub, "user:#{user_id}", {:websocket_message, message})
    Logger.debug("Broadcasted customization progress to user #{user_id}")
  end

  @doc """
  Broadcast application progress during auto-apply
  """
  def broadcast_application_progress(user_id, data) do
    message = %{
      type: "application_progress",
      data: data,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    PubSub.broadcast(@pubsub, "user:#{user_id}", {:websocket_message, message})
    Logger.debug("Broadcasted application progress to user #{user_id}")
  end

  @doc """
  Broadcast rate limit update
  """
  def broadcast_rate_limit_update(user_id, data) do
    message = %{
      type: "rate_limit_update",
      data: data,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    PubSub.broadcast(@pubsub, "user:#{user_id}", {:websocket_message, message})
    Logger.debug("Broadcasted rate limit update to user #{user_id}")
  end

  @doc """
  Broadcast application completion
  """
  def broadcast_application_completed(user_id, data) do
    message = %{
      type: "application_completed",
      data: data,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    PubSub.broadcast(@pubsub, "user:#{user_id}", {:websocket_message, message})
    Logger.info("Broadcasted application completion to user #{user_id}: #{inspect(data.job_title)}")
  end

  @doc """
  Generic broadcast update to a specific topic
  """
  def broadcast_update(topic, data) do
    message = %{
      type: "update",
      data: data,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    PubSub.broadcast(@pubsub, topic, {:websocket_message, message})
    Logger.debug("Broadcasted update to topic #{topic}")
  end

  @doc """
  Notify a specific topic with data (alias for broadcast_update)
  """
  def notify(topic, data) do
    broadcast_update(topic, data)
  end
end
