defmodule Core.AI.Prediction.Engine do
  @moduledoc """
  Predictive success models for job applications with continuous learning.

  Predicts:
  - Success probability (offer likelihood)
  - Response probability (hearing back)
  - Interview probability
  - Optimal application timing
  - Expected response time

  Uses historical data and ML models to continuously improve predictions.
  """

  require Logger
  alias Core.Repo
  alias Core.Schema.ApplicationPrediction
  alias Core.AI.Prediction.{Features, TimingOptimizer}
  alias Core.AI.Learning.FeedbackCollector
  import Ecto.Query

  @model_version "1.0.0"

  @doc """
  Predicts success probability for a job application.

  Considers:
  - User profile strength and history
  - Job-user match quality
  - Application timing
  - Market conditions
  - Company responsiveness patterns
  """
  def predict_success(job, user_id, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Predicting application success",
      job_id: job.id,
      user_id: user_id
    )

    with {:ok, features} <- Features.extract_prediction_features(job, user_id),
         {:ok, historical_data} <- fetch_historical_data(job, user_id),
         {:ok, probabilities} <- compute_probabilities(features, historical_data),
         {:ok, timing} <- TimingOptimizer.compute_optimal_timing(job, features),
         {:ok, saved_prediction} <- save_prediction(job, user_id, features, probabilities, timing, start_time) do

      Logger.info("Prediction completed",
        prediction_id: saved_prediction.id,
        success_probability: saved_prediction.success_probability
      )

      {:ok, saved_prediction}
    else
      {:error, reason} = error ->
        Logger.error("Prediction failed",
          job_id: job.id,
          user_id: user_id,
          reason: inspect(reason)
        )
        error
    end
  end

  @doc """
  Batch predicts for multiple jobs.
  """
  def batch_predict(jobs, user_id, opts \\ []) do
    Logger.info("Batch predicting applications", job_count: length(jobs), user_id: user_id)

    results =
      jobs
      |> Task.async_stream(
        fn job -> predict_success(job, user_id, opts) end,
        max_concurrency: 10,
        timeout: 30_000
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, reason}
      end)

    successes = Enum.filter(results, &match?({:ok, _}, &1))
    {:ok, %{predictions: successes, count: length(successes)}}
  end

  @doc """
  Records actual outcome for a prediction to enable learning.
  """
  def record_outcome(prediction_id, outcome, response_time_hours \\ nil) do
    prediction = Repo.get(ApplicationPrediction, prediction_id)

    if prediction do
      changeset = ApplicationPrediction.record_outcome_changeset(
        prediction,
        outcome,
        response_time_hours
      )

      case Repo.update(changeset) do
        {:ok, updated_prediction} ->
          # Collect feedback for continuous learning
          FeedbackCollector.collect_prediction_feedback(updated_prediction)

          Logger.info("Outcome recorded",
            prediction_id: prediction_id,
            outcome: outcome,
            accuracy: updated_prediction.prediction_accuracy
          )

          {:ok, updated_prediction}

        {:error, changeset} ->
          Logger.error("Failed to record outcome", prediction_id: prediction_id)
          {:error, changeset}
      end
    else
      {:error, :prediction_not_found}
    end
  end

  @doc """
  Gets predictions for a user, optionally filtered.
  """
  def get_user_predictions(user_id, opts \\ []) do
    query = from p in ApplicationPrediction,
      where: p.user_id == ^user_id,
      order_by: [desc: p.success_probability, desc: p.inserted_at]

    query = if limit = opts[:limit], do: limit(query, ^limit), else: query
    query = if min_prob = opts[:min_success_probability] do
      where(query, [p], p.success_probability >= ^min_prob)
    else
      query
    end

    Repo.all(query)
  end

  # Private functions

  defp fetch_historical_data(job, user_id) do
    # Fetch similar successful applications
    similar_jobs = fetch_similar_job_outcomes(job)
    user_history = fetch_user_application_history(user_id)
    company_stats = fetch_company_responsiveness(job.company)

    {:ok, %{
      similar_jobs: similar_jobs,
      user_history: user_history,
      company_stats: company_stats
    }}
  end

  defp fetch_similar_job_outcomes(job) do
    # Find applications to similar jobs and their outcomes
    # In production, use more sophisticated similarity matching
    query = from a in "applications",
      where: fragment("? ILIKE ?", a.job_title, ^"%#{job.title}%"),
      where: not is_nil(a.status),
      select: %{
        status: a.status,
        response_time: fragment("EXTRACT(EPOCH FROM (? - ?)) / 3600", a.updated_at, a.submitted_at)
      },
      limit: 100

    results = Repo.all(query)

    total = length(results)
    successes = Enum.count(results, fn r -> r.status in ["interview", "offer", "accepted"] end)

    %{
      total_count: total,
      success_count: successes,
      success_rate: if(total > 0, do: successes / total, else: 0.5),
      avg_response_time: calculate_avg_response_time(results)
    }
  end

  defp fetch_user_application_history(user_id) do
    query = from a in "applications",
      where: a.user_id == ^user_id,
      where: not is_nil(a.status),
      select: %{
        status: a.status,
        response_time: fragment("EXTRACT(EPOCH FROM (? - ?)) / 3600", a.updated_at, a.submitted_at)
      }

    results = Repo.all(query)

    total = length(results)
    successes = Enum.count(results, fn r -> r.status in ["interview", "offer", "accepted"] end)

    %{
      total_applications: total,
      success_count: successes,
      success_rate: if(total > 0, do: successes / total, else: 0.3),
      response_rate: if(total > 0, do: Enum.count(results, & &1.status != "pending") / total, else: 0.5)
    }
  end

  defp fetch_company_responsiveness(company_name) do
    # Analyze company's historical response patterns
    query = from a in "applications",
      join: j in "jobs", on: a.job_id == j.id,
      where: j.company == ^company_name,
      where: not is_nil(a.status),
      where: a.status != "pending",
      select: %{
        status: a.status,
        response_time: fragment("EXTRACT(EPOCH FROM (? - ?)) / 3600", a.updated_at, a.submitted_at)
      },
      limit: 50

    results = Repo.all(query)

    total = length(results)

    %{
      response_count: total,
      avg_response_time: calculate_avg_response_time(results),
      responsiveness_score: if(total > 5, do: min(total / 50.0, 1.0), else: 0.5)
    }
  end

  defp calculate_avg_response_time(results) do
    if length(results) > 0 do
      valid_times = Enum.reject(results, fn r -> is_nil(r.response_time) or r.response_time < 0 end)

      if length(valid_times) > 0 do
        sum = Enum.reduce(valid_times, 0, fn r, acc -> acc + r.response_time end)
        round(sum / length(valid_times))
      else
        72  # Default 3 days
      end
    else
      72
    end
  end

  defp compute_probabilities(features, historical_data) do
    # Compute base probabilities from features
    base_success = compute_base_success_probability(features)
    base_response = compute_response_probability(features, historical_data)

    # Adjust based on historical data
    adjusted_success = adjust_for_history(base_success, historical_data)
    adjusted_response = adjust_for_company_behavior(base_response, historical_data)

    # Compute conditional probabilities
    interview_prob = adjusted_success * 0.7  # If successful, 70% chance of interview
    offer_prob = adjusted_success * 0.3      # If successful, 30% chance of direct offer

    {:ok, %{
      success_probability: adjusted_success,
      response_probability: adjusted_response,
      interview_probability: interview_prob,
      offer_probability: offer_prob,
      factors: %{
        base_success: base_success,
        historical_adjustment: adjusted_success - base_success
      }
    }}
  end

  defp compute_base_success_probability(features) do
    # Weighted combination of factors
    weights = %{
      profile_strength: 0.30,
      match_quality: 0.35,
      timing: 0.15,
      market_demand: 0.10,
      competition: 0.10
    }

    profile_score = features.user_profile_strength
    match_score = features.job_match_quality
    timing_score = features.timing_score
    demand_score = features.market_demand_score
    competition_penalty = 1.0 - (features.competition_level / 10.0)

    score =
      profile_score * weights.profile_strength +
      match_score * weights.match_quality +
      timing_score * weights.timing +
      demand_score * weights.market_demand +
      competition_penalty * weights.competition

    # Clamp to [0.1, 0.9] to avoid overconfidence
    max(0.1, min(0.9, score))
  end

  defp compute_response_probability(features, historical_data) do
    company_score = historical_data.company_stats.responsiveness_score
    base_response = 0.6  # Base 60% chance of response

    # Adjust based on company responsiveness
    adjusted = base_response * (0.5 + company_score * 0.5)

    # Factor in user profile strength
    adjusted * (0.7 + features.user_profile_strength * 0.3)
  end

  defp adjust_for_history(base_probability, historical_data) do
    similar_success_rate = historical_data.similar_jobs.success_rate
    user_success_rate = historical_data.user_history.success_rate

    # Weighted average: 60% base model, 25% similar jobs, 15% user history
    adjusted =
      base_probability * 0.60 +
      similar_success_rate * 0.25 +
      user_success_rate * 0.15

    # Keep within reasonable bounds
    max(0.05, min(0.95, adjusted))
  end

  defp adjust_for_company_behavior(base_probability, historical_data) do
    company_score = historical_data.company_stats.responsiveness_score

    # If company rarely responds, reduce probability
    if company_score < 0.3 do
      base_probability * 0.7
    else
      base_probability
    end
  end

  defp save_prediction(job, user_id, features, probabilities, timing, start_time) do
    computation_time = System.monotonic_time(:millisecond) - start_time

    historical_data = features.historical_context

    attrs = %{
      user_id: user_id,
      job_id: job.id,
      job_external_id: job.external_id,
      success_probability: probabilities.success_probability,
      response_probability: probabilities.response_probability,
      interview_probability: probabilities.interview_probability,
      offer_probability: probabilities.offer_probability,
      predicted_response_time_hours: timing.predicted_response_time,
      predicted_review_time_hours: timing.predicted_review_time,
      optimal_application_time: timing.optimal_time,
      competition_level: timing.competition_level,
      user_profile_strength: features.user_profile_strength,
      job_match_quality: features.job_match_quality,
      timing_score: features.timing_score,
      market_demand_score: features.market_demand_score,
      company_responsiveness_score: features.company_responsiveness_score,
      similar_applications_count: historical_data.similar_count,
      similar_success_rate: historical_data.similar_success_rate,
      user_historical_success_rate: historical_data.user_success_rate,
      model_version: @model_version,
      confidence_interval: compute_confidence_interval(features, historical_data),
      prediction_factors: probabilities.factors,
      recommendations: generate_recommendations(probabilities, features),
      computation_time_ms: computation_time
    }

    %ApplicationPrediction{}
    |> ApplicationPrediction.changeset(attrs)
    |> Repo.insert()
  end

  defp compute_confidence_interval(features, historical_context) do
    # Confidence based on data availability and quality
    data_quality_factors = [
      historical_context.similar_count > 10,
      historical_context.user_applications > 5,
      features.user_profile_strength > 0.5,
      features.job_match_quality > 0.5
    ]

    confidence_score = Enum.count(data_quality_factors, & &1) / length(data_quality_factors)

    # Convert to confidence interval (higher is better)
    confidence_score * 0.3 + 0.6  # Range: 0.6 to 0.9
  end

  defp generate_recommendations(probabilities, features) do
    recommendations = []

    recommendations = if probabilities.success_probability < 0.5 do
      ["Consider improving profile match before applying" | recommendations]
    else
      recommendations
    end

    recommendations = if features.timing_score < 0.5 do
      ["Wait for optimal application timing to increase success" | recommendations]
    else
      recommendations
    end

    recommendations = if features.job_match_quality < 0.6 do
      ["Customize application to highlight relevant skills and experience" | recommendations]
    else
      recommendations
    end

    Enum.join(recommendations, ". ")
  end
end
