defmodule Core.AI.Orchestrator do
  @moduledoc """
  Intelligent application orchestrator with AI-powered timing optimization.

  Coordinates all AI components to:
  - Rank and prioritize jobs based on match scores and success predictions
  - Optimize application timing for maximum success
  - Manage rate limits intelligently
  - Auto-research companies before applying
  - Suggest optimal application strategies
  - Learn from outcomes and adapt

  This is the main entry point for AI-powered job application workflows.
  """

  require Logger
  alias Core.AI.{Matching, Prediction, Company, Analytics}
  alias Core.AI.Matching.Engine, as: MatchingEngine
  alias Core.AI.Prediction.Engine, as: PredictionEngine
  alias Core.AI.Company.ResearchEngine
  alias Core.AI.RateLimit.Optimizer, as: RateLimitOptimizer
  alias Core.Repo
  alias Core.Broadcaster
  import Ecto.Query

  @doc """
  Orchestrates intelligent job application workflow.

  Returns a prioritized list of jobs with:
  - AI match scores
  - Success predictions
  - Optimal timing recommendations
  - Company research insights
  - Application strategies

  ## Options
  - `:min_match_score` - Minimum match score (default: 0.5)
  - `:min_success_probability` - Minimum success probability (default: 0.4)
  - `:max_results` - Maximum jobs to return (default: 20)
  - `:include_research` - Include company research (default: true)
  - `:optimize_timing` - Optimize application timing (default: true)
  """
  def orchestrate_applications(user_id, available_jobs, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Orchestrating applications",
      user_id: user_id,
      job_count: length(available_jobs)
    )

    with {:ok, rate_strategy} <- RateLimitOptimizer.compute_optimal_rate(user_id, available_jobs, opts),
         {:ok, scored_jobs} <- score_and_rank_jobs(user_id, available_jobs, rate_strategy, opts),
         {:ok, prioritized} <- apply_intelligent_filtering(scored_jobs, rate_strategy, opts),
         {:ok, enriched} <- enrich_with_research(prioritized, opts),
         {:ok, strategy} <- generate_application_strategy(user_id, enriched, rate_strategy) do

      elapsed = System.monotonic_time(:millisecond) - start_time

      Logger.info("Orchestration complete",
        user_id: user_id,
        recommended_jobs: length(enriched),
        elapsed_ms: elapsed
      )

      # Track analytics
      Analytics.track_event("orchestration_completed", %{
        user_id: user_id,
        job_count: length(available_jobs),
        recommended_count: length(enriched),
        elapsed_ms: elapsed,
        strategy_type: strategy.strategy_type
      })

      # Broadcast to user
      broadcast_recommendations(user_id, enriched, strategy)

      {:ok, %{
        recommended_jobs: enriched,
        strategy: strategy,
        rate_strategy: rate_strategy,
        total_analyzed: length(available_jobs),
        computation_time_ms: elapsed
      }}
    else
      {:error, reason} = error ->
        Logger.error("Orchestration failed",
          user_id: user_id,
          reason: inspect(reason)
        )
        error
    end
  end

  @doc """
  Evaluates a single job for application readiness.

  Returns detailed analysis including:
  - Match score
  - Success prediction
  - Optimal timing
  - Company insights
  - Recommendation
  """
  def evaluate_job(job, user_id, opts \\ []) do
    Logger.info("Evaluating job", job_id: job.id, user_id: user_id)

    with {:ok, match_score} <- MatchingEngine.compute_match(job, user_id, opts),
         {:ok, prediction} <- PredictionEngine.predict_success(job, user_id, opts),
         {:ok, company_research} <- maybe_research_company(job.company, opts),
         {:ok, timing_recommendation} <- generate_timing_recommendation(prediction),
         {:ok, decision} <- make_application_decision(match_score, prediction, opts) do

      evaluation = %{
        job: job,
        match_score: match_score,
        prediction: prediction,
        company_research: company_research,
        timing: timing_recommendation,
        decision: decision,
        priority_score: calculate_overall_priority(match_score, prediction),
        recommendation: generate_job_recommendation(match_score, prediction, decision)
      }

      {:ok, evaluation}
    end
  end

  @doc """
  Optimizes application batch based on AI insights.

  Selects the best jobs to apply to within rate limits.
  """
  def optimize_batch(user_id, available_jobs, opts \\ []) do
    Logger.info("Optimizing application batch", user_id: user_id, job_count: length(available_jobs))

    with {:ok, batch_size} <- RateLimitOptimizer.recommend_batch_size(user_id, available_jobs),
         {:ok, orchestration} <- orchestrate_applications(user_id, available_jobs, opts) do

      # Select top N jobs based on priority
      optimal_batch = orchestration.recommended_jobs
        |> Enum.take(batch_size.recommended_batch_size)

      {:ok, %{
        batch: optimal_batch,
        batch_size: length(optimal_batch),
        batch_rationale: batch_size.rationale,
        total_candidates: length(available_jobs),
        strategy: orchestration.strategy
      }}
    end
  end

  @doc """
  Monitors application outcomes and triggers learning.
  """
  def record_application_outcome(application_id, outcome, opts \\ []) do
    Logger.info("Recording application outcome", application_id: application_id, outcome: outcome)

    # Fetch application details
    query = from a in "applications",
      where: a.id == ^application_id,
      select: a

    case Repo.one(query) do
      nil ->
        {:error, :application_not_found}

      application ->
        # Update prediction with actual outcome
        if application.success_prediction_id do
          PredictionEngine.record_outcome(
            application.success_prediction_id,
            outcome,
            opts[:response_time_hours]
          )
        end

        # Track analytics
        Analytics.track_event("application_outcome_recorded", %{
          application_id: application_id,
          user_id: application.user_id,
          outcome: outcome
        })

        {:ok, %{application_id: application_id, outcome: outcome}}
    end
  end

  # Private functions

  defp score_and_rank_jobs(user_id, jobs, rate_strategy, opts) do
    Logger.info("Scoring and ranking jobs", count: length(jobs))

    # Prioritize high-priority jobs from rate strategy
    high_priority_job_ids = Enum.map(rate_strategy.high_priority_jobs, fn p -> p.job.id end)

    scored = jobs
    |> Task.async_stream(
      fn job ->
        with {:ok, match_score} <- MatchingEngine.compute_match(job, user_id, opts),
             {:ok, prediction} <- PredictionEngine.predict_success(job, user_id, opts) do

          priority_boost = if job.id in high_priority_job_ids, do: 0.1, else: 0.0

          {:ok, %{
            job: job,
            match_score: match_score.overall_score,
            success_probability: prediction.success_probability,
            priority_score: calculate_priority_score(match_score, prediction) + priority_boost,
            prediction: prediction,
            match_details: match_score
          }}
        else
          error -> error
        end
      end,
      max_concurrency: 10,
      timeout: 30_000
    )
    |> Enum.map(fn
      {:ok, {:ok, result}} -> result
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.priority_score, :desc)

    {:ok, scored}
  end

  defp calculate_priority_score(match_score, prediction) do
    # Weighted combination of match score and success probability
    match_weight = 0.4
    success_weight = 0.6

    (match_score.overall_score * match_weight) + (prediction.success_probability * success_weight)
  end

  defp apply_intelligent_filtering(scored_jobs, rate_strategy, opts) do
    min_match = opts[:min_match_score] || 0.5
    min_success = opts[:min_success_probability] || 0.4
    max_results = opts[:max_results] || 20

    filtered = scored_jobs
    |> Enum.filter(fn job ->
      job.match_score >= min_match && job.success_probability >= min_success
    end)
    |> Enum.take(max_results)

    Logger.info("Filtered jobs",
      original: length(scored_jobs),
      filtered: length(filtered)
    )

    {:ok, filtered}
  end

  defp enrich_with_research(jobs, opts) do
    if opts[:include_research] == false do
      {:ok, jobs}
    else
      Logger.info("Enriching with company research", job_count: length(jobs))

      # Get unique companies
      companies = jobs
        |> Enum.map(fn j -> j.job.company end)
        |> Enum.uniq()

      # Research companies in batch
      {:ok, research_results} = ResearchEngine.batch_research_companies(companies)

      # Map research back to jobs
      research_map = research_results.researched
        |> Enum.map(fn {:ok, research} -> {research.company_name, research} end)
        |> Enum.into(%{})

      enriched = Enum.map(jobs, fn job ->
        Map.put(job, :company_research, research_map[job.job.company])
      end)

      {:ok, enriched}
    end
  end

  defp generate_application_strategy(user_id, jobs, rate_strategy) do
    # Analyze job distribution and characteristics
    high_success_count = Enum.count(jobs, fn j -> j.success_probability >= 0.7 end)
    medium_success_count = Enum.count(jobs, fn j ->
      j.success_probability >= 0.5 && j.success_probability < 0.7
    end)

    strategy_type = rate_strategy.strategy_type

    strategy = %{
      strategy_type: strategy_type,
      recommended_daily_applications: rate_strategy.recommended_daily_rate,
      immediate_applications: high_success_count,
      scheduled_applications: medium_success_count,
      phased_approach: length(jobs) > 20,
      timing_optimization_enabled: true,
      batch_recommendations: generate_batch_recommendations(jobs, rate_strategy),
      rationale: generate_strategy_rationale(strategy_type, jobs, rate_strategy)
    }

    {:ok, strategy}
  end

  defp generate_batch_recommendations(jobs, rate_strategy) do
    daily_rate = rate_strategy.recommended_daily_rate

    # Group by optimal timing
    immediate = Enum.filter(jobs, fn j ->
      DateTime.diff(j.prediction.optimal_application_time, DateTime.utc_now(), :hour) < 2
    end)

    scheduled = jobs -- immediate

    [
      %{
        batch: "immediate",
        count: min(length(immediate), round(daily_rate * 0.4)),
        timing: "within next 2 hours",
        priority: "high"
      },
      %{
        batch: "scheduled",
        count: min(length(scheduled), round(daily_rate * 0.6)),
        timing: "optimal times over next 24 hours",
        priority: "medium"
      }
    ]
  end

  defp generate_strategy_rationale(strategy_type, jobs, rate_strategy) do
    case strategy_type do
      :aggressive ->
        "High-quality opportunities detected (#{length(jobs)} jobs). Aggressive application strategy recommended to maximize success rate."

      :conservative ->
        "Limited high-probability opportunities. Focus on quality and timing optimization for best results."

      :balanced ->
        "Balanced approach recommended. Apply to #{rate_strategy.recommended_daily_rate} jobs daily, prioritizing high-match opportunities."
    end
  end

  defp maybe_research_company(company_name, opts) do
    if opts[:include_research] == false do
      {:ok, nil}
    else
      case ResearchEngine.get_company_research(company_name) do
        {:ok, research} -> {:ok, research}
        _ -> ResearchEngine.research_company(company_name)
      end
    end
  end

  defp generate_timing_recommendation(prediction) do
    optimal_time = prediction.optimal_application_time
    now = DateTime.utc_now()

    hours_until_optimal = DateTime.diff(optimal_time, now, :hour)

    recommendation = cond do
      hours_until_optimal <= 0 ->
        "Apply now - within optimal timing window"

      hours_until_optimal <= 2 ->
        "Apply within next 2 hours for optimal timing"

      hours_until_optimal <= 24 ->
        "Schedule application for #{Calendar.strftime(optimal_time, "%H:%M")} (#{hours_until_optimal}h from now)"

      true ->
        "Consider applying within next 24 hours, optimal time: #{Calendar.strftime(optimal_time, "%Y-%m-%d %H:%M")}"
    end

    {:ok, %{
      optimal_time: optimal_time,
      hours_until_optimal: hours_until_optimal,
      recommendation: recommendation,
      urgency: if(hours_until_optimal <= 2, do: "high", else: "medium")
    }}
  end

  defp make_application_decision(match_score, prediction, opts) do
    min_match = opts[:min_match_score] || 0.5
    min_success = opts[:min_success_probability] || 0.4

    decision = cond do
      match_score.overall_score >= 0.7 && prediction.success_probability >= 0.7 ->
        %{
          action: "apply_immediately",
          confidence: "high",
          reason: "Excellent match and high success probability"
        }

      match_score.overall_score >= min_match && prediction.success_probability >= min_success ->
        %{
          action: "apply_with_timing",
          confidence: "medium",
          reason: "Good match, optimize timing for better results"
        }

      match_score.overall_score < min_match ->
        %{
          action: "skip",
          confidence: "high",
          reason: "Match score below threshold"
        }

      prediction.success_probability < min_success ->
        %{
          action: "skip",
          confidence: "high",
          reason: "Success probability below threshold"
        }

      true ->
        %{
          action: "review_manually",
          confidence: "low",
          reason: "Borderline case, manual review recommended"
        }
    end

    {:ok, decision}
  end

  defp calculate_overall_priority(match_score, prediction) do
    # Consider multiple factors
    base_priority = (match_score.overall_score * 0.4) + (prediction.success_probability * 0.6)

    # Boost for optimal timing
    timing_boost = if prediction.timing_score > 0.7, do: 0.1, else: 0.0

    # Boost for high confidence
    confidence_boost = if prediction.confidence_interval > 0.7, do: 0.05, else: 0.0

    min(base_priority + timing_boost + confidence_boost, 1.0)
  end

  defp generate_job_recommendation(match_score, prediction, decision) do
    recommendations = []

    recommendations = if decision.action == "apply_immediately" do
      ["Strong candidate - apply immediately" | recommendations]
    else
      recommendations
    end

    recommendations = if length(match_score.missing_skills) > 0 do
      ["Highlight related experience for: #{Enum.join(Enum.take(match_score.missing_skills, 3), ", ")}" | recommendations]
    else
      recommendations
    end

    recommendations = if prediction.timing_score < 0.6 do
      ["Wait for optimal timing to improve success rate" | recommendations]
    else
      recommendations
    end

    recommendations = if prediction.competition_level == "high" do
      ["High competition - customize application thoroughly" | recommendations]
    else
      recommendations
    end

    Enum.join(recommendations, ". ")
  end

  defp broadcast_recommendations(user_id, jobs, strategy) do
    Broadcaster.broadcast_update("ai:recommendations:#{user_id}", %{
      recommended_count: length(jobs),
      strategy_type: strategy.strategy_type,
      immediate_actions: strategy.immediate_applications,
      daily_rate: strategy.recommended_daily_applications
    })
  end
end
