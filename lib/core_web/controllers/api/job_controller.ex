defmodule CoreWeb.Api.JobController do
  use CoreWeb, :controller

  plug :verify_orchestrator_secret

  def search(conn, params) do
    text = Map.get(params, "text")
    area = Map.get(params, "area")
    experience = Map.get(params, "experience")
    employment = Map.get(params, "employment")
    schedule = Map.get(params, "schedule")

    case Core.HH.Client.fetch_vacancies(%{
           text: text,
           area: area,
           experience: experience,
           employment: employment,
           schedule: schedule
         }) do
      {:ok, jobs} -> json(conn, %{jobs: jobs})
      {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  defp verify_orchestrator_secret(conn, _opts) do
    secret = conn |> get_req_header("x-core-secret") |> List.first()
    expected = System.get_env("ORCHESTRATOR_SECRET")

    if secret == expected do
      conn
    else
      conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized"}) |> halt()
    end
  end
end
