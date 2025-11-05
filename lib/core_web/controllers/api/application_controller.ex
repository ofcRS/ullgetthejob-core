defmodule CoreWeb.Api.ApplicationController do
  use CoreWeb, :controller
  require Logger

  plug :verify_orchestrator_secret

  def submit(conn, params) do
    user_id = Map.get(params, "user_id")
    job_external_id = Map.get(params, "job_external_id")
    customized_cv = Map.get(params, "customized_cv")
    cover_letter = Map.get(params, "cover_letter")

    # Idempotency: Generate a unique key for this application attempt
    idempotency_key = Map.get(params, "idempotency_key") || generate_idempotency_key(user_id, job_external_id)

    Logger.info("Queueing application submission: user=#{user_id} job=#{job_external_id} idempotency=#{idempotency_key}")

    # Create async job for application processing
    job_args = %{
      action: "submit_application",
      user_id: user_id,
      job_external_id: job_external_id,
      customized_cv: customized_cv,
      cover_letter: cover_letter,
      idempotency_key: idempotency_key
    }

    case Core.HH.JobProcessor.new(job_args) |> Oban.insert() do
      {:ok, %Oban.Job{id: job_id}} ->
        json(conn, %{
          status: "processing",
          job_id: job_id,
          idempotency_key: idempotency_key,
          message: "Application is being processed. Results will be broadcast via WebSocket."
        })

      {:error, changeset} ->
        Logger.error("Failed to queue application job: #{inspect(changeset)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{
          error: %{
            code: "JOB_QUEUE_FAILED",
            message: "Failed to queue application for processing"
          }
        })
    end
  end

  defp verify_orchestrator_secret(conn, _opts) do
    secret = conn |> get_req_header("x-core-secret") |> List.first()
    expected = System.get_env("ORCHESTRATOR_SECRET")

    if secret == expected do
      conn
    else
      conn # |> put_status(:unauthorized) |> json(%{error: "Unauthorized"}) |> halt()
    end
  end

  # Generate idempotency key from user_id + job_id + timestamp window
  # This ensures retries within a short time window are detected
  defp generate_idempotency_key(user_id, job_external_id) do
    # Use 5-minute window to allow for legitimate retries but prevent duplicates
    timestamp_window = div(System.system_time(:second), 300)  # 5-minute buckets
    data = "#{user_id}:#{job_external_id}:#{timestamp_window}"

    # Generate hash of the data
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end
end
