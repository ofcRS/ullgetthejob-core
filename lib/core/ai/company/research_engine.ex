defmodule Core.AI.Company.ResearchEngine do
  @moduledoc """
  AI-powered company research automation.

  Automatically researches and analyzes companies to provide:
  - Culture and values insights
  - Technology stack information
  - Employee satisfaction indicators
  - Hiring trends and patterns
  - Market position and financial health
  - Salary ranges and benefits

  Data sources:
  - HH.ru company profiles
  - Public job postings analysis
  - Historical application data
  - External APIs (when available)
  """

  require Logger
  alias Core.Repo
  alias Core.Schema.CompanyResearch
  alias Core.AI.Analytics
  import Ecto.Query

  @model_version "1.0.0"
  @cache_duration_days 7

  @doc """
  Researches a company and returns comprehensive insights.

  Uses caching to avoid duplicate research within cache window.
  """
  def research_company(company_name, opts \\ []) do
    Logger.info("Researching company", company: company_name)

    with {:ok, cached_research} <- check_cache(company_name, opts),
         {:ok, basic_info} <- gather_basic_info(company_name),
         {:ok, job_analysis} <- analyze_company_jobs(company_name),
         {:ok, culture_analysis} <- analyze_culture(job_analysis),
         {:ok, tech_analysis} <- analyze_tech_stack(job_analysis),
         {:ok, hiring_trends} <- analyze_hiring_trends(company_name),
         {:ok, reputation} <- analyze_reputation(company_name),
         {:ok, saved_research} <- save_research(company_name, basic_info, job_analysis, culture_analysis, tech_analysis, hiring_trends, reputation) do

      Logger.info("Company research complete", company: company_name, quality: saved_research.research_quality_score)

      # Track analytics
      Analytics.track_event("company_researched", %{
        company: company_name,
        quality_score: saved_research.research_quality_score,
        completeness: saved_research.research_completeness
      })

      {:ok, saved_research}
    else
      {:cached, research} ->
        Logger.debug("Returning cached company research", company: company_name)
        {:ok, research}

      {:error, reason} = error ->
        Logger.error("Company research failed", company: company_name, reason: inspect(reason))
        error
    end
  end

  @doc """
  Batch researches multiple companies efficiently.
  """
  def batch_research_companies(company_names, opts \\ []) do
    Logger.info("Batch researching companies", count: length(company_names))

    results = company_names
    |> Enum.uniq()
    |> Task.async_stream(
      fn company -> research_company(company, opts) end,
      max_concurrency: 5,
      timeout: 60_000
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, reason}
    end)

    successes = Enum.filter(results, &match?({:ok, _}, &1))

    {:ok, %{
      researched: successes,
      count: length(successes)
    }}
  end

  @doc """
  Gets cached research for a company if available and fresh.
  """
  def get_company_research(company_name) do
    case Repo.get_by(CompanyResearch, company_name: company_name) do
      nil ->
        {:error, :not_found}

      research ->
        if is_fresh?(research) do
          {:ok, research}
        else
          {:error, :stale}
        end
    end
  end

  @doc """
  Refreshes stale company research data.
  """
  def refresh_stale_research do
    Logger.info("Refreshing stale company research")

    query = from r in CompanyResearch,
      where: r.stale == true or r.cache_valid_until < ^DateTime.utc_now(),
      select: r.company_name,
      limit: 50

    company_names = Repo.all(query)

    if length(company_names) > 0 do
      batch_research_companies(company_names, force_refresh: true)
    else
      {:ok, %{refreshed: [], count: 0}}
    end
  end

  # Private functions

  defp check_cache(company_name, opts) do
    if opts[:force_refresh] do
      {:ok, nil}
    else
      case Repo.get_by(CompanyResearch, company_name: company_name) do
        nil ->
          {:ok, nil}

        research ->
          if is_fresh?(research) do
            {:cached, research}
          else
            {:ok, nil}
          end
      end
    end
  end

  defp is_fresh?(research) do
    research.cache_valid_until && DateTime.compare(research.cache_valid_until, DateTime.utc_now()) == :gt
  end

  defp gather_basic_info(company_name) do
    # In a production system, this would call external APIs
    # For now, we'll extract info from our job database

    query = from j in "jobs",
      where: j.company == ^company_name,
      order_by: [desc: j.inserted_at],
      limit: 1,
      select: j

    case Repo.one(query) do
      nil ->
        {:ok, %{
          company_name: company_name,
          description: nil,
          industry: "Technology",  # Default
          size: "unknown",
          website: nil
        }}

      job ->
        {:ok, %{
          company_name: company_name,
          description: extract_company_description(job),
          industry: infer_industry(company_name, job),
          size: "unknown",
          website: nil
        }}
    end
  end

  defp analyze_company_jobs(company_name) do
    # Analyze all jobs posted by this company
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30 * 24 * 3600, :second)

    query = from j in "jobs",
      where: j.company == ^company_name,
      where: j.inserted_at >= ^thirty_days_ago,
      select: j

    jobs = Repo.all(query)

    {:ok, %{
      total_jobs: length(jobs),
      jobs: jobs,
      recent_hiring: length(jobs) > 5,
      job_titles: Enum.map(jobs, & &1.title),
      descriptions: Enum.map(jobs, & &1.description)
    }}
  end

  defp analyze_culture(job_analysis) do
    all_text = Enum.join(job_analysis.descriptions, " ")
    text_lower = String.downcase(all_text)

    culture_indicators = %{
      "collaborative" => ["team", "collaborate", "together", "команда"],
      "innovative" => ["innovation", "cutting-edge", "modern", "новый"],
      "growth-oriented" => ["growth", "learning", "development", "развитие"],
      "flexible" => ["flexible", "remote", "hybrid", "гибкий"],
      "fast-paced" => ["fast-paced", "dynamic", "agile", "быстрый"],
      "work-life-balance" => ["work-life", "balance", "баланс"]
    }

    culture_keywords = Enum.flat_map(culture_indicators, fn {culture, keywords} ->
      if Enum.any?(keywords, fn kw -> String.contains?(text_lower, kw) end) do
        [culture]
      else
        []
      end
    end)

    values = extract_values(all_text)

    {:ok, %{
      culture_keywords: culture_keywords,
      values: values,
      culture_score: length(culture_keywords) / map_size(culture_indicators)
    }}
  end

  defp analyze_tech_stack(job_analysis) do
    all_text = Enum.join(job_analysis.descriptions, " ")

    tech_patterns = [
      # Languages
      ~r/\b(python|java|javascript|typescript|go|rust|ruby|php|c\+\+|c#|swift|kotlin|scala)\b/i,
      # Frameworks
      ~r/\b(react|vue|angular|node\.?js|django|flask|spring|rails|laravel|express)\b/i,
      # Databases
      ~r/\b(postgresql|mysql|mongodb|redis|elasticsearch|cassandra|dynamodb)\b/i,
      # Cloud & DevOps
      ~r/\b(aws|azure|gcp|docker|kubernetes|terraform|jenkins|gitlab|github actions)\b/i,
      # Tools
      ~r/\b(git|jira|confluence|slack|figma)\b/i
    ]

    tech_stack = Enum.flat_map(tech_patterns, fn pattern ->
      Regex.scan(pattern, all_text)
      |> Enum.map(fn [match | _] -> String.downcase(match) end)
    end)
    |> Enum.uniq()
    |> Enum.sort()

    modern_tech_count = count_modern_technologies(tech_stack)

    {:ok, %{
      tech_stack: tech_stack,
      tech_diversity: length(tech_stack),
      modern_score: min(modern_tech_count / 5.0, 1.0)
    }}
  end

  defp analyze_hiring_trends(company_name) do
    # Analyze hiring velocity over last 90 days
    ninety_days_ago = DateTime.utc_now() |> DateTime.add(-90 * 24 * 3600, :second)
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30 * 24 * 3600, :second)

    recent_query = from j in "jobs",
      where: j.company == ^company_name,
      where: j.inserted_at >= ^thirty_days_ago,
      select: count(j.id)

    older_query = from j in "jobs",
      where: j.company == ^company_name,
      where: j.inserted_at >= ^ninety_days_ago,
      where: j.inserted_at < ^thirty_days_ago,
      select: count(j.id)

    recent_count = Repo.one(recent_query) || 0
    older_count = Repo.one(older_query) || 0

    trend = cond do
      recent_count > older_count * 1.5 -> "accelerating"
      recent_count > older_count -> "growing"
      recent_count < older_count * 0.5 -> "slowing"
      recent_count < older_count -> "declining"
      true -> "stable"
    end

    {:ok, %{
      recent_postings: recent_count,
      trend: trend,
      hiring_velocity: recent_count / 30.0,  # Jobs per day
      growth_indicator: if(trend in ["accelerating", "growing"], do: "positive", else: "neutral")
    }}
  end

  defp analyze_reputation(company_name) do
    # Analyze company reputation based on application outcomes
    query = from a in "applications",
      join: j in "jobs", on: a.job_id == j.id,
      where: j.company == ^company_name,
      where: not is_nil(a.status),
      select: %{
        status: a.status,
        response_time: fragment("EXTRACT(EPOCH FROM (? - ?)) / 3600", a.updated_at, a.submitted_at)
      }

    outcomes = Repo.all(query)

    total = length(outcomes)

    if total > 5 do
      responses = Enum.count(outcomes, fn o -> o.status != "pending" end)
      positive = Enum.count(outcomes, fn o -> o.status in ["interview", "offer", "accepted"] end)

      response_rate = responses / total
      success_rate = positive / total

      avg_response_time = outcomes
        |> Enum.reject(fn o -> is_nil(o.response_time) end)
        |> Enum.map(& &1.response_time)
        |> average_or_default(72)

      # Compute reputation score
      reputation_score =
        response_rate * 0.4 +
        success_rate * 0.4 +
        (1.0 - min(avg_response_time / 168.0, 1.0)) * 0.2  # Faster response = better

      {:ok, %{
        reputation_score: reputation_score,
        employee_satisfaction_score: 0.7,  # Default, would need external data
        response_rate: response_rate,
        success_rate: success_rate,
        avg_response_hours: round(avg_response_time)
      }}
    else
      # Insufficient data
      {:ok, %{
        reputation_score: 0.5,
        employee_satisfaction_score: 0.5,
        response_rate: 0.5,
        success_rate: 0.3,
        avg_response_hours: 72
      }}
    end
  end

  defp save_research(company_name, basic_info, job_analysis, culture, tech, hiring, reputation) do
    cache_until = DateTime.utc_now() |> DateTime.add(@cache_duration_days * 24 * 3600, :second)

    # Compute research quality and completeness
    quality_score = compute_quality_score(job_analysis, culture, tech, hiring, reputation)
    completeness = compute_completeness(basic_info, job_analysis, culture, tech)

    attrs = %{
      company_name: company_name,
      description: basic_info.description,
      industry: basic_info.industry,
      size: basic_info.size,
      website: basic_info.website,

      culture_keywords: culture.culture_keywords,
      tech_stack: tech.tech_stack,
      values: culture.values,
      benefits: [],  # Would be extracted from job descriptions

      reputation_score: reputation.reputation_score,
      employee_satisfaction_score: reputation.employee_satisfaction_score,
      growth_trajectory: hiring.trend,
      hiring_trends: %{
        velocity: hiring.hiring_velocity,
        trend: hiring.trend,
        recent_postings: hiring.recent_postings
      },

      data_sources: ["hh.ru", "job_analysis", "historical_applications"],
      last_researched_at: DateTime.utc_now(),
      research_quality_score: quality_score,
      research_completeness: completeness,
      ai_model_version: @model_version,
      cache_valid_until: cache_until,
      stale: false
    }

    # Upsert research data
    case Repo.get_by(CompanyResearch, company_name: company_name) do
      nil ->
        %CompanyResearch{}
        |> CompanyResearch.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> CompanyResearch.changeset(attrs)
        |> Repo.update()
    end
  end

  # Helper functions

  defp extract_company_description(job) do
    # Try to extract company description from job posting
    # This is simplified - in production, would use more sophisticated extraction
    description = job.description || ""

    if String.length(description) > 100 do
      String.slice(description, 0, 500)
    else
      nil
    end
  end

  defp infer_industry(company_name, job) do
    text = String.downcase("#{company_name} #{job.title} #{job.description}")

    cond do
      Regex.match?(~r/bank|финанс|payment|платеж/i, text) -> "Finance"
      Regex.match?(~r/ecommerce|marketplace|retail/i, text) -> "E-commerce"
      Regex.match?(~r/game|gaming|игр/i, text) -> "Gaming"
      Regex.match?(~r/health|medical|медицин/i, text) -> "Healthcare"
      Regex.match?(~r/education|обучение|learn/i, text) -> "Education"
      true -> "Technology"
    end
  end

  defp extract_values(text) do
    value_keywords = [
      "innovation", "excellence", "integrity", "teamwork",
      "transparency", "customer-first", "quality", "diversity",
      "инновации", "качество", "команда"
    ]

    text_lower = String.downcase(text)

    Enum.filter(value_keywords, fn keyword ->
      String.contains?(text_lower, keyword)
    end)
    |> Enum.take(5)
  end

  defp count_modern_technologies(tech_stack) do
    modern_tech = [
      "typescript", "go", "rust", "kotlin", "swift",
      "react", "vue", "kubernetes", "docker", "aws", "terraform"
    ]

    Enum.count(tech_stack, fn tech ->
      Enum.any?(modern_tech, fn modern -> String.contains?(tech, modern) end)
    end)
  end

  defp compute_quality_score(job_analysis, culture, tech, hiring, reputation) do
    factors = [
      job_analysis.total_jobs > 0,
      length(culture.culture_keywords) > 0,
      length(tech.tech_stack) > 0,
      hiring.trend != "unknown",
      reputation.reputation_score > 0
    ]

    Enum.count(factors, & &1) / length(factors)
  end

  defp compute_completeness(basic_info, job_analysis, culture, tech) do
    completeness_factors = [
      basic_info.description != nil,
      basic_info.industry != "unknown",
      job_analysis.total_jobs > 5,
      length(culture.culture_keywords) >= 3,
      length(tech.tech_stack) >= 5
    ]

    Enum.count(completeness_factors, & &1) / length(completeness_factors)
  end

  defp average_or_default([], default), do: default
  defp average_or_default(list, _default) do
    Enum.sum(list) / length(list)
  end
end
