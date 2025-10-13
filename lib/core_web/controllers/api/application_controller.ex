defmodule CoreWeb.Api.ApplicationController do
  use CoreWeb, :controller

  plug :verify_orchestrator_secret

  def submit(conn, params) do
    user_id = Map.get(params, "user_id")
    job_external_id = Map.get(params, "job_external_id")
    customized_cv = Map.get(params, "customized_cv")
    cover_letter = Map.get(params, "cover_letter")

    with {:ok, resume_id} <- Core.HH.Client.get_or_create_resume(user_id, customized_cv),
         :ok <- Core.HH.Client.publish_resume(resume_id),
         {:ok, negotiation_id} <- Core.HH.Client.submit_application(job_external_id, resume_id, cover_letter) do
      json(conn, %{
        success: true,
        resume_id: resume_id,
        negotiation_id: negotiation_id,
        submitted_at: DateTime.utc_now()
      })
    else
      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
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
end
