defmodule Core.AI.Matching.Engine do
  @moduledoc """
  AI-powered job matching engine with multi-factor scoring.

  This engine analyzes jobs and user profiles to compute comprehensive
  match scores across multiple dimensions:
  - Skills alignment
  - Experience fit
  - Salary expectations
  - Location preferences
  - Company culture match
  - Career growth potential
  - Benefits alignment

  The engine uses a combination of:
  - Semantic similarity analysis
  - Feature extraction and comparison
  - ML-based scoring models
  - Historical success data
  """

  require Logger
  alias Core.Repo
  alias Core.Schema.AiJobMatchingScore
  alias Core.AI.Matching.{Scorer, FeatureExtractor}
  alias Core.AI.Analytics

  @model_version "1.0.0"

  @doc """
  Computes a comprehensive match score for a job and user.

  ## Options
  - `:cv_id` - Specific CV to use for matching
  - `:force_recompute` - Skip cache and recompute score
  - `:include_details` - Include detailed analysis in response

  ## Returns
  - `{:ok, %AiJobMatchingScore{}}` - Match score with details
  - `{:error, reason}` - Error occurred during computation
  """
  def compute_match(job, user_id, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Computing AI match score",
      job_id: job.id,
      user_id: user_id,
      model_version: @model_version
    )

    with {:ok, cached_score} <- check_cache(job.id, user_id, opts),
         {:ok, user_profile} <- fetch_user_profile(user_id, opts[:cv_id]),
         {:ok, job_features} <- FeatureExtractor.extract_job_features(job),
         {:ok, user_features} <- FeatureExtractor.extract_user_features(user_profile),
         {:ok, scores} <- Scorer.compute_scores(job_features, user_features),
         {:ok, saved_score} <- save_score(job, user_id, scores, user_profile, start_time) do

      # Track analytics event
      Analytics.track_event("job_match_computed", %{
        user_id: user_id,
        job_id: job.id,
        overall_score: saved_score.overall_score,
        computation_time_ms: saved_score.computation_time_ms,
        cached: false
      })

      {:ok, saved_score}
    else
      {:cached, score} ->
        Logger.debug("Returning cached match score", score_id: score.id)
        {:ok, score}

      {:error, reason} = error ->
        Logger.error("Failed to compute match score",
          job_id: job.id,
          user_id: user_id,
          reason: inspect(reason)
        )
        error
    end
  end

  @doc """
  Batch computes match scores for multiple jobs.

  More efficient than computing individually as it reuses user profile data.
  """
  def batch_compute_matches(jobs, user_id, opts \\ []) do
    Logger.info("Batch computing match scores",
      job_count: length(jobs),
      user_id: user_id
    )

    with {:ok, user_profile} <- fetch_user_profile(user_id, opts[:cv_id]),
         {:ok, user_features} <- FeatureExtractor.extract_user_features(user_profile) do

      results =
        jobs
        |> Task.async_stream(
          fn job ->
            compute_match_with_features(job, user_id, user_features, user_profile, opts)
          end,
          max_concurrency: 10,
          timeout: 30_000
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, reason} -> {:error, reason}
        end)

      successes = Enum.filter(results, &match?({:ok, _}, &1))
      failures = Enum.filter(results, &match?({:error, _}, &1))

      Logger.info("Batch computation complete",
        successes: length(successes),
        failures: length(failures)
      )

      {:ok, %{successes: successes, failures: failures}}
    end
  end

  @doc """
  Gets the top N matched jobs for a user.
  """
  def get_top_matches(user_id, limit \\ 20, opts \\ []) do
    min_score = opts[:min_score] || 0.5
    max_age_hours = opts[:max_age_hours] || 24

    cutoff_time = DateTime.utc_now() |> DateTime.add(-max_age_hours * 3600, :second)

    AiJobMatchingScore
    |> where([s], s.user_id == ^user_id)
    |> where([s], s.overall_score >= ^min_score)
    |> where([s], s.inserted_at >= ^cutoff_time)
    |> order_by([s], desc: s.overall_score)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Invalidates cached scores for a job or user.
  """
  def invalidate_cache(job_id: job_id) do
    AiJobMatchingScore
    |> where([s], s.job_id == ^job_id)
    |> Repo.delete_all()
  end

  def invalidate_cache(user_id: user_id) do
    AiJobMatchingScore
    |> where([s], s.user_id == ^user_id)
    |> Repo.delete_all()
  end

  # Private functions

  defp check_cache(job_id, user_id, opts) do
    if opts[:force_recompute] do
      {:ok, nil}
    else
      case Repo.get_by(AiJobMatchingScore, job_id: job_id, user_id: user_id) do
        nil -> {:ok, nil}
        score -> check_score_freshness(score)
      end
    end
  end

  defp check_score_freshness(score) do
    max_age_hours = 24
    age = DateTime.diff(DateTime.utc_now(), score.inserted_at, :hour)

    if age < max_age_hours do
      {:cached, score}
    else
      {:ok, nil}
    end
  end

  defp fetch_user_profile(user_id, cv_id) do
    # TODO: Implement proper user profile fetching
    # For now, return mock data structure
    {:ok, %{
      user_id: user_id,
      cv_id: cv_id,
      skills: [],
      experience_years: 0,
      education: [],
      preferences: %{},
      parsed_data: %{}
    }}
  end

  defp compute_match_with_features(job, user_id, user_features, user_profile, opts) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, cached_score} <- check_cache(job.id, user_id, opts),
         {:ok, job_features} <- FeatureExtractor.extract_job_features(job),
         {:ok, scores} <- Scorer.compute_scores(job_features, user_features),
         {:ok, saved_score} <- save_score(job, user_id, scores, user_profile, start_time) do
      {:ok, saved_score}
    else
      {:cached, score} -> {:ok, score}
      error -> error
    end
  end

  defp save_score(job, user_id, scores, user_profile, start_time) do
    computation_time = System.monotonic_time(:millisecond) - start_time

    attrs = %{
      user_id: user_id,
      job_id: job.id,
      job_external_id: job.external_id,
      cv_id: user_profile.cv_id,
      overall_score: scores.overall_score,
      skill_match_score: scores.skill_match_score,
      experience_match_score: scores.experience_match_score,
      salary_match_score: scores.salary_match_score,
      location_match_score: scores.location_match_score,
      company_culture_score: scores.company_culture_score,
      career_growth_score: scores.career_growth_score,
      benefits_score: scores.benefits_score,
      matching_skills: scores.matching_skills,
      missing_skills: scores.missing_skills,
      growth_opportunities: scores.growth_opportunities,
      concerns: scores.concerns,
      recommendations: scores.recommendations,
      model_version: @model_version,
      confidence_level: scores.confidence_level,
      scoring_factors: scores.factors,
      computation_time_ms: computation_time,
      cached: false
    }

    %AiJobMatchingScore{}
    |> AiJobMatchingScore.changeset(attrs)
    |> Repo.insert()
  end
end
