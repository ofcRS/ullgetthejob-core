defmodule Core.HH.JobProcessor do
  @moduledoc """
  Oban worker for processing HH.ru job applications asynchronously.
  Handles resume creation, publishing, and application submission.
  """
  use Oban.Worker,
    queue: :hh_api,
    max_attempts: 3,
    priority: 1,
    tags: ["hh", "application"]

  require Logger
  alias Core.{HH, Broadcaster}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "action" => "submit_application",
          "user_id" => user_id,
          "job_external_id" => job_external_id,
          "customized_cv" => customized_cv,
          "cover_letter" => cover_letter,
          "idempotency_key" => idempotency_key
        }
      }) do
    Logger.info(
      "Processing HH.ru application: user=#{user_id} job=#{job_external_id} idempotency=#{idempotency_key}"
    )

    with {:ok, access_token} <- HH.OAuth.get_valid_token(user_id),
         {:ok, resume_id} <- HH.Client.get_or_create_resume(access_token, customized_cv),
         :ok <- HH.Client.publish_resume(access_token, resume_id),
         {:ok, negotiation_id} <-
           HH.Client.submit_application(access_token, job_external_id, resume_id, cover_letter) do
      result = %{
        success: true,
        resume_id: resume_id,
        negotiation_id: negotiation_id,
        submitted_at: DateTime.utc_now(),
        idempotency_key: idempotency_key
      }

      # Broadcast success to user via WebSocket
      broadcast_result(user_id, :success, result)

      {:ok, result}
    else
      {:error, {:http_error, 400, body}} = error ->
        # Handle resume not found by creating a fallback
        if resume_not_found?(body) do
          handle_resume_fallback(
            user_id,
            job_external_id,
            customized_cv,
            cover_letter,
            idempotency_key
          )
        else
          Logger.error("Application failed: #{inspect(error)}")
          broadcast_result(user_id, :error, %{error: "bad_request", details: body})
          {:error, error}
        end

      {:error, :no_valid_token} = error ->
        Logger.error("No valid HH.ru token for user #{user_id}")
        broadcast_result(user_id, :error, %{error: "token_expired"})
        {:error, error}

      {:error, reason} = error ->
        Logger.error("Application processing failed: #{inspect(reason)}")
        broadcast_result(user_id, :error, %{error: "processing_failed", reason: inspect(reason)})
        {:error, error}
    end
  end

  defp handle_resume_fallback(user_id, job_external_id, customized_cv, cover_letter, idempotency_key) do
    Logger.info("Attempting fallback resume creation for user=#{user_id}")

    new_title = fallback_unique_title(customized_cv)
    cv2 = customized_cv |> Map.put("hh_resume_id", nil) |> Map.put("title", new_title)

    with {:ok, access_token} <- HH.OAuth.get_valid_token(user_id),
         {:ok, resume_id2} <- HH.Client.get_or_create_resume(access_token, cv2),
         :ok <- HH.Client.publish_resume(access_token, resume_id2),
         {:ok, negotiation_id} <-
           HH.Client.submit_application(access_token, job_external_id, resume_id2, cover_letter) do
      result = %{
        success: true,
        resume_id: resume_id2,
        negotiation_id: negotiation_id,
        submitted_at: DateTime.utc_now(),
        fallback_used: true,
        idempotency_key: idempotency_key
      }

      broadcast_result(user_id, :success, result)
      {:ok, result}
    else
      error ->
        Logger.error("Fallback resume creation failed: #{inspect(error)}")
        broadcast_result(user_id, :error, %{error: "fallback_failed"})
        {:error, error}
    end
  end

  defp resume_not_found?(body) do
    map =
      case body do
        %{} = m -> m
        bin when is_binary(bin) -> Jason.decode(bin) |> elem(1)
        _ -> %{}
      end

    by_error_value =
      map
      |> Map.get("errors", [])
      |> Enum.any?(fn e -> Map.get(e, "value") == "resume_not_found" end)

    by_bad_arg = Map.get(map, "bad_argument") == "resume_id"

    by_error_value or by_bad_arg
  end

  defp fallback_unique_title(customized_cv) do
    base = Map.get(customized_cv, "title") || "Resume"
    suffix = System.system_time(:millisecond) |> Integer.to_string()
    "#{base} (UGTJ #{suffix})"
  end

  defp broadcast_result(user_id, status, data) do
    try do
      Broadcaster.notify("user:#{user_id}:applications", %{
        status: status,
        data: data,
        timestamp: DateTime.utc_now()
      })
    rescue
      e ->
        Logger.warning("Failed to broadcast result: #{inspect(e)}")
    end
  end
end
