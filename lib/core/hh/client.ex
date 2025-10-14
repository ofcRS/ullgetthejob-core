defmodule Core.HH.Client do
  @moduledoc """
  Minimal HH.ru API client for fetching vacancies.

  Authentication: Bearer token from env `HH_ACCESS_TOKEN`.
  """

  require Logger

  @base_url "https://api.hh.ru"

  @doc """
  Fetch vacancies from HH.ru using supported params.

  Supported params:
  - :text, :area, :experience, :employment, :schedule

  Returns {:ok, [job, ...]} or {:error, reason}
  """
  @spec fetch_vacancies(map()) :: {:ok, list(map())} | {:error, any()}
  def fetch_vacancies(params \\ %{}) do
    token = System.get_env("HH_ACCESS_TOKEN")
    headers =
      case token do
        nil -> []
        "" -> []
        token -> [{"Authorization", "Bearer #{token}"}]
      end

    query =
      params
      |> Map.take([:text, :area, :experience, :employment, :schedule])
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Enum.into(%{})

    case Req.get("#{@base_url}/vacancies", headers: headers, params: query) do
      {:ok, %{status: 200, body: body}} ->
        data = decode_body(body)
        items = Map.get(data, "items", [])
        {:ok, Enum.map(items, &normalize_vacancy/1)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("HH API error status=#{status} body=#{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("HH API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetch authenticated user's resumes using access token.
  GET /resumes/mine
  """
  @spec fetch_user_resumes(binary()) :: {:ok, list(map())} | {:error, any()}
  def fetch_user_resumes(access_token) when is_binary(access_token) do
    headers = [{"Authorization", "Bearer #{access_token}"}]
    case Req.get("#{@base_url}/resumes/mine", headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        data = decode_body(body)
        {:ok, Map.get(data, "items", [])}
      {:ok, %{status: status, body: body}} ->
        Logger.error("HH API resumes error status=#{status} body=#{inspect(body)}")
        {:error, {:http_error, status}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetch resume details by id.
  GET /resumes/:id
  """
  @spec fetch_resume_details(binary(), binary()) :: {:ok, map()} | {:error, any()}
  def fetch_resume_details(resume_id, access_token) when is_binary(resume_id) and is_binary(access_token) do
    headers = [{"Authorization", "Bearer #{access_token}"}]
    case Req.get("#{@base_url}/resumes/#{resume_id}", headers: headers) do
      {:ok, %{status: 200, body: body}} -> {:ok, decode_body(body)}
      {:ok, %{status: status, body: body}} ->
        Logger.error("HH API resume details error status=#{status} body=#{inspect(body)}")
        {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_body(%{} = body), do: body
  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} -> map
      _ -> %{}
    end
  end

  defp normalize_vacancy(item) do
    %{
      hh_vacancy_id: item["id"],
      id: item["id"],
      title: item["name"],
      company: get_in(item, ["employer", "name"]),
      salary: render_salary(item["salary"]),
      area: get_in(item, ["area", "name"]),
      url: item["alternate_url"],
      skills: [],
      description: build_description(item),
      has_test: Map.get(item, "has_test", false),
      test_required: Map.get(item, "has_test", false)
    }
  end

  defp render_salary(nil), do: nil
  defp render_salary(%{"from" => from, "to" => to, "currency" => currency}) do
    cond do
      from && to -> "#{from}-#{to} #{currency}"
      from -> "from #{from} #{currency}"
      to -> "to #{to} #{currency}"
      true -> nil
    end
  end
  defp render_salary(_), do: nil

  defp build_description(item) do
    req = get_in(item, ["snippet", "requirement"]) || ""
    resp = get_in(item, ["snippet", "responsibility"]) || ""
    [req, resp]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> String.trim()
  end

  @doc """
  Ensure a resume exists for the user and return its id. Placeholder implementation.
  """
  @spec get_or_create_resume(binary(), map()) :: {:ok, binary()} | {:error, any()}
  def get_or_create_resume(_user_id, _customized_cv) do
    {:ok, Ecto.UUID.generate()}
  end

  @doc """
  Publish resume on HH.ru. Placeholder no-op.
  """
  @spec publish_resume(binary()) :: :ok | {:error, any()}
  def publish_resume(_resume_id), do: :ok

  @doc """
  Submit application to HH.ru. Placeholder implementation returning negotiation id.
  """
  @spec submit_application(binary(), binary(), binary() | nil) :: {:ok, binary()} | {:error, any()}
  def submit_application(_job_external_id, _resume_id, _cover_letter) do
    {:ok, Ecto.UUID.generate()}
  end
end
