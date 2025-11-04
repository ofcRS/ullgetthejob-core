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
    # This prevents duplicate applications if the client retries
    idempotency_key = Map.get(params, "idempotency_key") || generate_idempotency_key(user_id, job_external_id)

    Logger.info("Processing application submission: user=#{user_id} job=#{job_external_id} idempotency_key=#{idempotency_key}")

    # Check if we've already processed this idempotency key recently
    # For now, just log it. TODO: Implement proper idempotency cache (Redis/ETS)
    # This would check a cache and return the previous response if found
    # if cached_response = check_idempotency_cache(idempotency_key) do
    #   return cached_response
    # end

    with {:ok, access_token} <- Core.HH.OAuth.get_valid_token(user_id),
         {:ok, resume_id} <- Core.HH.Client.get_or_create_resume(access_token, customized_cv),
         :ok <- Core.HH.Client.publish_resume(access_token, resume_id),
         {:ok, negotiation_id} <- Core.HH.Client.submit_application(access_token, job_external_id, resume_id, cover_letter) do
      response = %{
        success: true,
        resume_id: resume_id,
        negotiation_id: negotiation_id,
        submitted_at: DateTime.utc_now(),
        idempotency_key: idempotency_key
      }

      # TODO: Cache this response for 24 hours using idempotency_key
      # store_idempotency_response(idempotency_key, response)

      json(conn, response)
    else
      {:error, {:http_error, 400, body}} ->
        # Fallback: if HH says resume is not found/available during negotiation, force-create a fresh resume and retry once
        if resume_not_found_reason?(body) do
          new_title = fallback_unique_title(customized_cv)
          cv2 = customized_cv |> Map.put("hh_resume_id", nil) |> Map.put("title", new_title)

          with {:ok, access_token} <- Core.HH.OAuth.get_valid_token(user_id),
               {:ok, resume_id2} <- Core.HH.Client.get_or_create_resume(access_token, cv2),
               :ok <- Core.HH.Client.publish_resume(access_token, resume_id2),
               {:ok, negotiation_id} <- Core.HH.Client.submit_application(access_token, job_external_id, resume_id2, cover_letter) do
            json(conn, %{
              success: true,
              resume_id: resume_id2,
              negotiation_id: negotiation_id,
              submitted_at: DateTime.utc_now(),
              fallback_used: true
            })
          else
            {:error, {:forbidden, details}} ->
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Cannot apply to this vacancy", details: details})

            {:error, {:bad_arguments, body}} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "bad_arguments", details: body})

            {:error, reason} ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
          end
        else
          conn |> put_status(:unprocessable_entity) |> json(%{error: inspect({:http_error, 400, body})})
        end

      {:error, :no_valid_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "HH.ru not connected or token expired"})

      {:error, :missing_resume_id} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "missing_resume_id"})

      {:error, :resume_not_available} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "resume_not_available"})

      {:error, {:bad_arguments, body}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "bad_arguments", details: body})

      {:error, {:forbidden, details}} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Cannot apply to this vacancy", details: details})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  defp resume_not_found_reason?(body) do
    map =
      case body do
        %{} = m -> m
        bin when is_binary(bin) ->
          case Jason.decode(bin) do
            {:ok, m} -> m
            _ -> %{}
          end
        _ -> %{}
      end

    by_error_value =
      map
      |> Map.get("errors", [])
      |> List.wrap()
      |> Enum.any?(fn e -> (Map.get(e, "value") || Map.get(e, :value)) == "resume_not_found" end)

    by_desc =
      map
      |> Map.get("description")
      |> to_string()
      |> String.downcase()
      |> (fn s -> String.contains?(s, "resume not found") or String.contains?(s, "not available") end).()

    by_bad_arg = (Map.get(map, "bad_argument") || Map.get(map, :bad_argument)) == "resume_id"

    by_error_value or (by_desc and by_bad_arg)
  end

  defp fallback_unique_title(customized_cv) do
    base = Map.get(customized_cv, "title") || Map.get(customized_cv, :title) || "Resume"
    suffix = System.system_time(:millisecond) |> Integer.to_string()
    base <> " (UGTJ " <> suffix <> ")"
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
