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

  def show(conn, %{"id" => id}) when is_binary(id) do
    case Core.HH.Client.fetch_vacancy_details(id) do
      {:ok, details} ->
        job = build_job(details, id)
        json(conn, %{success: true, job: job})

      {:error, {:http_error, status}} ->
        conn
        |> put_status(status || 502)
        |> json(%{success: false, error: "HH API returned status #{status}"})

      {:error, reason} ->
        conn
        |> put_status(502)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  def show(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{success: false, error: "Missing vacancy id"})
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

  defp build_job(details, fallback_id) do
    id = Map.get(details, "id", fallback_id)
    %{
      id: id,
      hh_vacancy_id: id,
      title: Map.get(details, "name"),
      company: get_in(details, ["employer", "name"]),
      salary: format_salary(Map.get(details, "salary")),
      area: get_in(details, ["area", "name"]),
      url: Map.get(details, "alternate_url"),
      has_test: Map.get(details, "has_test", false),
      description: sanitize_description(Map.get(details, "description")),
      skills: extract_key_skills(details),
      full_description_loaded: true
    }
  end

  defp sanitize_description(nil), do: ""
  defp sanitize_description(description) when is_binary(description) do
    description
    |> Regex.replace(~r/<[^>]*>/, " ")
    |> Regex.replace(~r/\s+/, " ")
    |> String.trim()
  end
  defp sanitize_description(other), do: to_string(other)

  defp extract_key_skills(details) do
    details
    |> Map.get("key_skills", [])
    |> Enum.reduce([], fn
      %{"name" => name}, acc when is_binary(name) -> [name | acc]
      _, acc -> acc
    end)
    |> Enum.reverse()
  end

  defp format_salary(nil), do: nil
  defp format_salary(%{"from" => from, "to" => to, "currency" => currency}) do
    cond do
      from && to -> "#{from}-#{to} #{currency}"
      from -> "from #{from} #{currency}"
      to -> "to #{to} #{currency}"
      true -> nil
    end
  end
  defp format_salary(_), do: nil
end
