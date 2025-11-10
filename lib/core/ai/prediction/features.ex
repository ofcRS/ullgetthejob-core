defmodule Core.AI.Prediction.Features do
  @moduledoc """
  Feature extraction for application success prediction.

  Extracts and computes features used by the prediction engine:
  - User profile strength metrics
  - Job-user match quality
  - Timing factors
  - Market demand indicators
  - Historical context
  """

  require Logger
  alias Core.Repo
  alias Core.AI.Matching.Engine, as: MatchingEngine
  import Ecto.Query

  @doc """
  Extracts comprehensive features for prediction.
  """
  def extract_prediction_features(job, user_id) do
    Logger.debug("Extracting prediction features", job_id: job.id, user_id: user_id)

    with {:ok, user_profile} <- fetch_user_profile(user_id),
         {:ok, match_score} <- get_or_compute_match_score(job, user_id),
         {:ok, timing_features} <- extract_timing_features(job),
         {:ok, market_features} <- extract_market_features(job),
         {:ok, historical_context} <- extract_historical_context(job, user_id) do

      features = %{
        # Core prediction factors
        user_profile_strength: compute_profile_strength(user_profile),
        job_match_quality: match_score.overall_score,
        timing_score: timing_features.score,
        market_demand_score: market_features.demand_score,
        company_responsiveness_score: market_features.company_score,
        competition_level: market_features.competition_level,

        # Supporting data
        user_profile: user_profile,
        match_score: match_score,
        timing_features: timing_features,
        market_features: market_features,
        historical_context: historical_context
      }

      {:ok, features}
    end
  end

  # User profile strength computation
  defp compute_profile_strength(profile) do
    factors = [
      # Profile completeness
      compute_completeness_score(profile),

      # Experience relevance
      compute_experience_score(profile),

      # Skill diversity
      compute_skill_score(profile),

      # Historical success rate
      compute_historical_success_score(profile)
    ]

    Enum.sum(factors) / length(factors)
  end

  defp compute_completeness_score(profile) do
    # Check for key profile elements
    required_fields = [
      profile[:skills] && length(profile[:skills]) > 0,
      profile[:experience_years] && profile[:experience_years] > 0,
      profile[:education] && length(profile[:education]) > 0,
      profile[:summary] && String.length(profile[:summary] || "") > 50
    ]

    Enum.count(required_fields, & &1) / length(required_fields)
  end

  defp compute_experience_score(profile) do
    years = profile[:experience_years] || 0

    # Normalize experience (0-15 years -> 0.0-1.0)
    min(years / 15.0, 1.0)
  end

  defp compute_skill_score(profile) do
    skills = profile[:skills] || []
    skill_count = length(skills)

    # Normalize skill count (0-30 skills -> 0.0-1.0)
    min(skill_count / 30.0, 1.0)
  end

  defp compute_historical_success_score(profile) do
    # Use cached success rate if available
    profile[:success_rate] || 0.5
  end

  # Timing feature extraction
  defp extract_timing_features(job) do
    now = DateTime.utc_now()
    fetched_at = job.fetched_at || job.inserted_at

    # Calculate job age in hours
    job_age_hours = DateTime.diff(now, fetched_at, :hour)

    # Optimal application time is within first 48 hours of posting
    timing_score = cond do
      job_age_hours < 24 -> 1.0   # Within first day - excellent
      job_age_hours < 48 -> 0.8   # Within 2 days - good
      job_age_hours < 168 -> 0.6  # Within a week - moderate
      true -> 0.3                  # Older - lower priority
    end

    {:ok, %{
      score: timing_score,
      job_age_hours: job_age_hours,
      is_fresh: job_age_hours < 48,
      urgency: calculate_urgency(job, job_age_hours)
    }}
  end

  defp calculate_urgency(job, age_hours) do
    # Check for urgency indicators in job description
    description = String.downcase(job.description || "")

    urgency_keywords = ["urgent", "immediate", "asap", "срочно"]
    has_urgency_keyword = Enum.any?(urgency_keywords, fn kw ->
      String.contains?(description, kw)
    end)

    cond do
      has_urgency_keyword -> "high"
      age_hours < 24 -> "high"
      age_hours < 168 -> "medium"
      true -> "low"
    end
  end

  # Market demand feature extraction
  defp extract_market_features(job) do
    # Analyze market demand for this job type
    job_title_pattern = "%#{job.title}%"

    # Count similar jobs in last 30 days
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30 * 24 * 3600, :second)

    similar_jobs_query = from j in "jobs",
      where: fragment("? ILIKE ?", j.title, ^job_title_pattern),
      where: j.inserted_at >= ^thirty_days_ago,
      select: count(j.id)

    similar_job_count = Repo.one(similar_jobs_query) || 0

    # Higher count = higher demand
    demand_score = min(similar_job_count / 50.0, 1.0)

    # Estimate competition level (more jobs = more competition)
    competition_level = cond do
      similar_job_count > 100 -> "very_high"
      similar_job_count > 50 -> "high"
      similar_job_count > 20 -> "medium"
      similar_job_count > 5 -> "low"
      true -> "very_low"
    end

    # Company responsiveness score
    company_score = fetch_company_score(job.company)

    {:ok, %{
      demand_score: demand_score,
      similar_job_count: similar_job_count,
      competition_level: competition_level,
      company_score: company_score
    }}
  end

  defp fetch_company_score(company_name) do
    # Query historical application response rates for this company
    query = from a in "applications",
      join: j in "jobs", on: a.job_id == j.id,
      where: j.company == ^company_name,
      where: not is_nil(a.status),
      select: %{
        responded: a.status != "pending",
        total: 1
      }

    results = Repo.all(query)
    total = length(results)

    if total > 5 do
      responded = Enum.count(results, & &1.responded)
      responded / total
    else
      0.5  # Neutral score for unknown companies
    end
  end

  # Historical context extraction
  defp extract_historical_context(job, user_id) do
    # Similar job applications
    similar_apps = count_similar_applications(job)

    # User's application history
    user_apps = count_user_applications(user_id)
    user_success = calculate_user_success_rate(user_id)

    {:ok, %{
      similar_count: similar_apps.total,
      similar_success_rate: similar_apps.success_rate,
      user_applications: user_apps.total,
      user_success_rate: user_success
    }}
  end

  defp count_similar_applications(job) do
    job_title_pattern = "%#{job.title}%"

    query = from a in "applications",
      join: j in "jobs", on: a.job_id == j.id,
      where: fragment("? ILIKE ?", j.title, ^job_title_pattern),
      where: not is_nil(a.status),
      select: %{
        status: a.status,
        total: 1
      }

    results = Repo.all(query)
    total = length(results)
    successes = Enum.count(results, fn r -> r.status in ["interview", "offer", "accepted"] end)

    %{
      total: total,
      success_rate: if(total > 0, do: successes / total, else: 0.5)
    }
  end

  defp count_user_applications(user_id) do
    query = from a in "applications",
      where: a.user_id == ^user_id,
      select: count(a.id)

    total = Repo.one(query) || 0

    %{total: total}
  end

  defp calculate_user_success_rate(user_id) do
    query = from a in "applications",
      where: a.user_id == ^user_id,
      where: not is_nil(a.status),
      select: %{
        status: a.status,
        total: 1
      }

    results = Repo.all(query)
    total = length(results)

    if total > 0 do
      successes = Enum.count(results, fn r -> r.status in ["interview", "offer", "accepted"] end)
      successes / total
    else
      0.5  # Neutral for new users
    end
  end

  # Helper functions

  defp fetch_user_profile(user_id) do
    # TODO: Implement proper profile fetching
    # For now, return mock structure
    {:ok, %{
      user_id: user_id,
      skills: [],
      experience_years: 3,
      education: [],
      summary: "",
      success_rate: 0.5
    }}
  end

  defp get_or_compute_match_score(job, user_id) do
    # Try to get existing match score, compute if not exists
    case MatchingEngine.compute_match(job, user_id) do
      {:ok, score} -> {:ok, score}
      _ ->
        # Return default score if matching fails
        {:ok, %{overall_score: 0.5}}
    end
  end
end
