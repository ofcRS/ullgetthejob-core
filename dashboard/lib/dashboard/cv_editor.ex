defmodule Dashboard.CVEditor do
  @moduledoc """
  Context module for CV editing and customization using AI.
  """
  require Logger
  import Ecto.Query

  alias Dashboard.AI.OpenRouterClient
  alias Dashboard.CVs
  alias Dashboard.CVs.CustomCV
  alias Dashboard.Jobs
  alias Dashboard.Repo

  @doc """
  Analyzes job requirements from a job description.
  """
  def analyze_job_requirements(job_description) when is_binary(job_description) do
    OpenRouterClient.analyze_job_requirements(job_description)
  end

  @doc """
  Suggests CV highlights based on CV data and job requirements.
  """
  def suggest_highlights(cv_data, job_requirements) do
    OpenRouterClient.suggest_cv_highlights(cv_data, job_requirements)
  end

  @doc """
  Generates a custom CV for a specific job.

  Returns {:ok, custom_cv} or {:error, reason}
  """
  def generate_custom_cv(cv_id, job_id, opts \\ []) do
    with {:ok, cv} <- get_cv(cv_id),
         {:ok, job} <- get_job(job_id),
         {:ok, job_requirements} <- analyze_job_from_db(job),
         {:ok, suggestions} <- suggest_highlights(cv.parsed_data, job_requirements) do

      custom_data = merge_suggestions(cv.parsed_data, suggestions)

      attrs = %{
        cv_id: cv.id,
        job_id: job.id,
        job_title: job.title,
        customized_data: custom_data,
        ai_suggestions: suggestions
      }

      # Generate cover letter if requested
      attrs =
        if Keyword.get(opts, :generate_cover_letter, true) do
          case generate_cover_letter(cv.parsed_data, job) do
            {:ok, cover_letter} ->
              Map.put(attrs, :cover_letter, cover_letter)
            {:error, _} ->
              attrs
          end
        else
          attrs
        end

      %CustomCV{}
      |> CustomCV.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Generates a cover letter for a job application.
  """
  def generate_cover_letter(cv_data, job) when is_map(cv_data) and is_map(job) do
    # Build job description from job data
    job_description = build_job_description(job)
    OpenRouterClient.generate_cover_letter(cv_data, job_description)
  end

  def generate_cover_letter(cv_data, job_description) when is_binary(job_description) do
    OpenRouterClient.generate_cover_letter(cv_data, job_description)
  end

  @doc """
  Updates an existing custom CV.
  """
  def update_custom_cv(%CustomCV{} = custom_cv, attrs) do
    custom_cv
    |> CustomCV.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets a custom CV by ID.
  """
  def get_custom_cv(id) do
    case Repo.get(CustomCV, id) do
      nil -> {:error, :not_found}
      custom_cv -> {:ok, Repo.preload(custom_cv, [:cv, :job])}
    end
  end

  @doc """
  Lists all custom CVs for a given CV.
  """
  def list_custom_cvs_for_cv(cv_id) do
    from(c in CustomCV,
      where: c.cv_id == ^cv_id,
      order_by: [desc: c.inserted_at],
      preload: [:job]
    )
    |> Repo.all()
  end

  # Private functions

  defp get_cv(cv_id) do
    case CVs.get_cv(cv_id) do
      nil -> {:error, :cv_not_found}
      cv -> {:ok, cv}
    end
  end

  defp get_job(job_id) do
    case Jobs.get_job_by_external_id(job_id) do
      nil ->
        case Repo.get(Dashboard.Jobs.Job, job_id) do
          nil -> {:error, :job_not_found}
          job -> {:ok, job}
        end
      job ->
        {:ok, job}
    end
  end

  defp analyze_job_from_db(job) do
    job_description = build_job_description(job)
    analyze_job_requirements(job_description)
  end

  defp build_job_description(job) do
    """
    Job Title: #{job.title}
    Company: #{job.company || "Not specified"}
    Location: #{job.area || "Not specified"}
    Salary: #{job.salary || "Not specified"}

    #{if job.url, do: "Job URL: #{job.url}", else: ""}
    """
  end

  defp merge_suggestions(cv_data, suggestions) do
    # Start with original CV data
    customized = cv_data

    # Apply recommended ordering if provided
    customized =
      if suggested_order = Map.get(suggestions, "suggested_order") do
        apply_suggested_order(customized, suggested_order)
      else
        customized
      end

    # Highlight recommended experiences
    customized =
      if recommended_exp = Map.get(suggestions, "recommended_experiences") do
        highlight_experiences(customized, recommended_exp)
      else
        customized
      end

    # Filter and reorder skills
    customized =
      if recommended_skills = Map.get(suggestions, "recommended_skills") do
        Map.put(customized, "skills", recommended_skills)
      else
        customized
      end

    customized
  end

  defp apply_suggested_order(cv_data, suggested_order) do
    Enum.reduce(suggested_order, cv_data, fn {section, order}, acc ->
      section_str = to_string(section)

      if items = Map.get(acc, section_str) do
        reordered = reorder_items(items, order)
        Map.put(acc, section_str, reordered)
      else
        acc
      end
    end)
  end

  defp reorder_items(items, order) when is_list(items) and is_list(order) do
    indexed = Enum.with_index(items)

    Enum.map(order, fn idx ->
      Enum.find_value(indexed, fn {item, i} ->
        if i == idx, do: item
      end)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp reorder_items(items, _order), do: items

  defp highlight_experiences(cv_data, recommended) do
    if experiences = Map.get(cv_data, "experience") do
      highlighted =
        Enum.map(experiences, fn exp ->
          case Enum.find(recommended, fn rec ->
            Map.get(rec, "experience_index") == Enum.find_index(experiences, &(&1 == exp))
          end) do
            nil ->
              exp
            rec ->
              exp
              |> Map.put("highlighted", true)
              |> Map.put("relevance_score", Map.get(rec, "relevance_score"))
              |> Map.put("relevance_reason", Map.get(rec, "reason"))
          end
        end)

      Map.put(cv_data, "experience", highlighted)
    else
      cv_data
    end
  end
end
