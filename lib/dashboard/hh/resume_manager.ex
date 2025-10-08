defmodule Dashboard.HH.ResumeManager do
  @moduledoc """
  Manages resumes on HH.ru via API.

  API Docs: https://github.com/hhru/api/blob/master/docs/resumes.md
  """
  require Logger

  alias Dashboard.HH.Client

  @doc """
  Lists all resumes for the authenticated user.

  Returns: {:ok, [%{id: "...", title: "...", ...}]} or {:error, reason}
  """
  def list_resumes do
    case Client.get("/resumes/mine") do
      {:ok, %{"items" => resumes}} ->
        {:ok, resumes}

      {:ok, response} ->
        Logger.warning("Unexpected response: #{inspect(response)}")
        {:error, :unexpected_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets full resume details by ID.
  """
  def get_resume(resume_id) do
    Client.get("/resumes/#{resume_id}")
  end

  @doc """
  Creates a new resume on HH.ru from our CV data.

  Resume structure: https://github.com/hhru/api/blob/master/docs/resumes.md#resume-fields
  """
  def create_resume(cv_data, opts \\ []) do
    resume_data = build_resume_json(cv_data, opts)

    case Client.post("/resumes", resume_data) do
      {:ok, %{"id" => resume_id} = response} ->
        Logger.info("Created resume on HH.ru: #{resume_id}")
        {:ok, response}

      {:ok, response} ->
        Logger.error("Failed to create resume: #{inspect(response)}")
        {:error, {:creation_failed, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates an existing resume.
  """
  def update_resume(resume_id, cv_data, opts \\ []) do
    resume_data = build_resume_json(cv_data, opts)

    Client.put("/resumes/#{resume_id}", resume_data)
  end

  @doc """
  Publishes a resume (makes it visible to employers).
  """
  def publish_resume(resume_id) do
    Client.post("/resumes/#{resume_id}/publish", %{})
  end

  # Private functions

  defp build_resume_json(cv_data, opts) do
    personal_info = Map.get(cv_data, "personal_info", %{})

    %{
      # Basic info
      last_name: extract_last_name(personal_info),
      first_name: extract_first_name(personal_info),
      middle_name: nil,

      # Title
      title: Keyword.get(opts, :title) || Map.get(personal_info, "title", "Resume"),

      # Contact info
      contact: build_contact(personal_info),

      # Experience
      experience: build_experience(cv_data),

      # Skills
      skill_set: build_skills(cv_data),

      # Education
      education: build_education(cv_data),

      # Additional
      language: [%{id: "eng", level: %{id: "l1"}}]
    }
  end

  defp extract_first_name(personal_info) do
    case Map.get(personal_info, "name", "") |> String.split(" ") do
      [first | _] -> first
      _ -> "User"
    end
  end

  defp extract_last_name(personal_info) do
    case Map.get(personal_info, "name", "") |> String.split(" ") do
      [_, last | _] -> last
      _ -> ""
    end
  end

  defp build_contact(personal_info) do
    [
      %{
        type: %{id: "email"},
        value: Map.get(personal_info, "email", "")
      },
      %{
        type: %{id: "cell"},
        value: Map.get(personal_info, "phone", "")
      }
    ]
    |> Enum.reject(fn contact -> contact.value == "" end)
  end

  defp build_experience(cv_data) do
    cv_data
    |> Map.get("experience", [])
    |> Enum.map(fn exp ->
      %{
        company: Map.get(exp, "company", ""),
        position: Map.get(exp, "title", ""),
        description: Map.get(exp, "description", ""),
        start: parse_date_for_hh(Map.get(exp, "period", "")),
        end: nil
      }
    end)
  end

  defp build_skills(cv_data) do
    skills = Map.get(cv_data, "skills", [])

    if Enum.empty?(skills) do
      []
    else
      [Enum.join(skills, ", ")]
    end
  end

  defp build_education(cv_data) do
    cv_data
    |> Map.get("education", [])
    |> Enum.map(fn edu ->
      %{
        name: Map.get(edu, "institution", ""),
        organization: Map.get(edu, "institution", ""),
        result: Map.get(edu, "degree", ""),
        year: parse_year(Map.get(edu, "year", ""))
      }
    end)
  end

  defp parse_date_for_hh(period_string) do
    # Extract year from strings like "2020 - 2023" or "Jan 2020 - Present"
    case Regex.run(~r/\d{4}/, period_string) do
      [year] -> String.to_integer(year)
      _ -> DateTime.utc_now().year
    end
  end

  defp parse_year(year_string) do
    case Integer.parse(to_string(year_string)) do
      {year, _} when year > 1950 and year < 2030 -> year
      _ -> DateTime.utc_now().year
    end
  end
end
