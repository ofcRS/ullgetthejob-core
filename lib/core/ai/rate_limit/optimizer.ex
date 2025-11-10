defmodule Core.AI.RateLimit.Optimizer do
  @moduledoc """
  Smart rate limit optimizer using AI to dynamically adjust application rates.

  Optimizes rate limiting based on:
  - User success patterns and response rates
  - Company responsiveness
  - Application quality scores
  - Time-of-day and day-of-week patterns
  - Historical outcomes

  Goals:
  - Maximize applications to high-probability jobs
  - Minimize wasted applications to low-probability jobs
  - Respect platform limits while optimizing allocation
  - Adapt to user-specific patterns
  """

  require Logger
  alias Core.RateLimiter
  alias Core.Repo
  alias Core.AI.Prediction.Engine, as: PredictionEngine
  alias Core.AI.Analytics
  import Ecto.Query

  @default_daily_limit 200  # HH.ru platform limit
  @min_success_probability 0.4

  @doc """
  Computes optimal rate limit allocation for a user.

  Returns recommended application rate and priority ordering.
  """
  def compute_optimal_rate(user_id, available_jobs, opts \\ []) do
    Logger.info("Computing optimal rate allocation", user_id: user_id, job_count: length(available_jobs))

    with {:ok, user_metrics} <- analyze_user_metrics(user_id),
         {:ok, job_priorities} <- compute_job_priorities(available_jobs, user_id),
         {:ok, rate_strategy} <- compute_rate_strategy(user_metrics, job_priorities, opts) do

      Logger.info("Rate optimization complete",
        user_id: user_id,
        recommended_daily_rate: rate_strategy.recommended_daily_rate,
        high_priority_jobs: length(rate_strategy.high_priority_jobs)
      )

      # Track analytics
      Analytics.track_event("rate_limit_optimized", %{
        user_id: user_id,
        daily_rate: rate_strategy.recommended_daily_rate,
        strategy: rate_strategy.strategy_type
      })

      {:ok, rate_strategy}
    end
  end

  @doc """
  Determines if an application should be allowed based on AI optimization.

  Returns:
  - `{:allow, priority}` - Application should proceed with given priority
  - `{:defer, reason}` - Application should be deferred
  - `{:reject, reason}` - Application should be skipped
  """
  def should_allow_application?(user_id, job, opts \\ []) do
    with {:ok, tokens_available} <- RateLimiter.check_tokens(user_id),
         {:ok, prediction} <- PredictionEngine.predict_success(job, user_id, opts),
         {:ok, priority} <- calculate_priority(prediction, tokens_available) do

      decision = make_decision(prediction, tokens_available, priority, opts)

      Logger.debug("Application decision",
        user_id: user_id,
        job_id: job.id,
        decision: decision,
        success_prob: prediction.success_probability,
        priority: priority
      )

      decision
    else
      {:error, :rate_limited} ->
        {:defer, "Rate limit reached, wait for token refill"}

      {:error, reason} ->
        {:reject, "Failed to compute decision: #{inspect(reason)}"}
    end
  end

  @doc """
  Adjusts rate limits dynamically based on recent performance.
  """
  def adjust_rate_limits(user_id) do
    Logger.info("Adjusting rate limits", user_id: user_id)

    with {:ok, performance} <- analyze_recent_performance(user_id),
         {:ok, new_rate} <- compute_adjusted_rate(user_id, performance) do

      # Update rate limiter configuration if needed
      # This would require extending the RateLimiter to support dynamic rates

      Logger.info("Rate limits adjusted",
        user_id: user_id,
        new_rate: new_rate,
        performance_score: performance.score
      )

      {:ok, %{new_rate: new_rate, performance: performance}}
    end
  end

  @doc """
  Recommends optimal batch size for applications based on current conditions.
  """
  def recommend_batch_size(user_id, available_jobs) do
    with {:ok, tokens} <- RateLimiter.check_tokens(user_id),
         {:ok, user_metrics} <- analyze_user_metrics(user_id) do

      # Calculate recommended batch size
      base_batch = min(tokens, 20)  # Never apply to more than 20 at once

      # Adjust based on user success rate
      adjusted_batch = if user_metrics.success_rate > 0.6 do
        base_batch  # High success rate, use full allocation
      else
        max(round(base_batch * 0.6), 5)  # Lower success, be more selective
      end

      # Filter for high-quality jobs
      high_quality_count = Enum.count(available_jobs, fn job ->
        # Quick heuristic without full prediction
        job_quality_score(job) > 0.6
      end)

      recommended = min(adjusted_batch, high_quality_count)

      {:ok, %{
        recommended_batch_size: recommended,
        available_tokens: tokens,
        high_quality_jobs: high_quality_count,
        rationale: generate_batch_rationale(recommended, tokens, user_metrics)
      }}
    end
  end

  # Private functions

  defp analyze_user_metrics(user_id) do
    # Analyze last 30 days of application data
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30 * 24 * 3600, :second)

    query = from a in "applications",
      where: a.user_id == ^user_id,
      where: a.submitted_at >= ^thirty_days_ago,
      select: %{
        total: count(a.id),
        status: a.status
      },
      group_by: a.status

    results = Repo.all(query)

    total = Enum.reduce(results, 0, fn r, acc -> acc + r.total end)
    successes = Enum.reduce(results, 0, fn r, acc ->
      if r.status in ["interview", "offer", "accepted"], do: acc + r.total, else: acc
    end)
    responses = Enum.reduce(results, 0, fn r, acc ->
      if r.status != "pending", do: acc + r.total, else: acc
    end)

    metrics = %{
      total_applications: total,
      success_count: successes,
      response_count: responses,
      success_rate: if(total > 0, do: successes / total, else: 0.3),
      response_rate: if(total > 0, do: responses / total, else: 0.6),
      avg_daily_applications: total / 30.0
    }

    {:ok, metrics}
  end

  defp compute_job_priorities(jobs, user_id) do
    # Compute priority for each job
    priorities = jobs
    |> Enum.map(fn job ->
      # Quick priority score without full prediction
      priority_score = job_quality_score(job)

      %{
        job: job,
        priority_score: priority_score,
        category: categorize_priority(priority_score)
      }
    end)
    |> Enum.sort_by(& &1.priority_score, :desc)

    {:ok, priorities}
  end

  defp job_quality_score(job) do
    # Quick heuristic scoring
    factors = []

    # Freshness
    age_hours = DateTime.diff(DateTime.utc_now(), job.inserted_at, :hour)
    freshness = if age_hours < 48, do: 1.0, else: 0.5
    factors = [freshness | factors]

    # Salary indicator
    salary_score = if job.salary, do: 0.8, else: 0.5
    factors = [salary_score | factors]

    # Description quality
    desc_length = String.length(job.description || "")
    desc_score = if desc_length > 500, do: 0.9, else: 0.6
    factors = [desc_score | factors]

    Enum.sum(factors) / length(factors)
  end

  defp categorize_priority(score) do
    cond do
      score >= 0.7 -> :high
      score >= 0.5 -> :medium
      true -> :low
    end
  end

  defp compute_rate_strategy(user_metrics, job_priorities, _opts) do
    # Determine strategy based on user metrics and job quality
    strategy_type = determine_strategy_type(user_metrics, job_priorities)

    high_priority = Enum.filter(job_priorities, & &1.category == :high)
    medium_priority = Enum.filter(job_priorities, & &1.category == :medium)

    recommended_rate = calculate_recommended_rate(user_metrics, length(high_priority))

    {:ok, %{
      strategy_type: strategy_type,
      recommended_daily_rate: recommended_rate,
      high_priority_jobs: high_priority,
      medium_priority_jobs: medium_priority,
      allocation: %{
        high_priority_allocation: min(recommended_rate * 0.6, length(high_priority)),
        medium_priority_allocation: min(recommended_rate * 0.3, length(medium_priority)),
        low_priority_allocation: recommended_rate * 0.1
      },
      rationale: generate_strategy_rationale(strategy_type, user_metrics)
    }}
  end

  defp determine_strategy_type(user_metrics, job_priorities) do
    high_quality_ratio = Enum.count(job_priorities, & &1.category == :high) / max(length(job_priorities), 1)

    cond do
      # High success rate and many quality jobs - aggressive
      user_metrics.success_rate > 0.6 && high_quality_ratio > 0.3 ->
        :aggressive

      # Low success rate - conservative
      user_metrics.success_rate < 0.3 ->
        :conservative

      # Moderate performance - balanced
      true ->
        :balanced
    end
  end

  defp calculate_recommended_rate(user_metrics, high_quality_job_count) do
    base_rate = case user_metrics.avg_daily_applications do
      avg when avg > 0 -> round(avg * 1.2)  # 20% increase over current
      _ -> 20  # Default for new users
    end

    # Adjust based on success rate
    adjusted_rate = if user_metrics.success_rate > 0.5 do
      base_rate
    else
      round(base_rate * 0.7)  # Reduce rate for low success
    end

    # Cap at platform limit and available high-quality jobs
    min(@default_daily_limit, max(adjusted_rate, min(high_quality_job_count, 10)))
  end

  defp calculate_priority(prediction, tokens_available) do
    # Calculate priority based on multiple factors
    success_factor = prediction.success_probability * 0.6
    urgency_factor = calculate_urgency_factor(prediction) * 0.2
    scarcity_factor = calculate_scarcity_factor(tokens_available) * 0.2

    priority = success_factor + urgency_factor + scarcity_factor

    {:ok, priority}
  end

  defp calculate_urgency_factor(prediction) do
    # Higher urgency if job is fresh
    optimal_time = prediction.optimal_application_time
    now = DateTime.utc_now()

    diff_hours = abs(DateTime.diff(optimal_time, now, :hour))

    if diff_hours < 2 do
      1.0  # Very urgent
    else
      max(0.3, 1.0 - (diff_hours / 48.0))  # Decay over 48 hours
    end
  end

  defp calculate_scarcity_factor(tokens_available) do
    # When tokens are scarce, be more selective
    if tokens_available < 5 do
      0.9  # High scarcity, need high priority
    else
      0.3  # Plenty of tokens, less critical
    end
  end

  defp make_decision(prediction, tokens_available, priority, opts) do
    min_probability = opts[:min_probability] || @min_success_probability
    force = opts[:force] || false

    cond do
      # Force application regardless of prediction
      force ->
        {:allow, priority}

      # High priority and good success probability
      prediction.success_probability >= min_probability && priority >= 0.6 ->
        {:allow, priority}

      # Medium priority but low tokens - defer
      tokens_available < 5 && priority < 0.7 ->
        {:defer, "Low token availability, save for higher priority applications"}

      # Low success probability
      prediction.success_probability < min_probability ->
        {:reject, "Success probability below threshold (#{Float.round(prediction.success_probability, 2)} < #{min_probability})"}

      # Medium priority
      priority >= 0.4 ->
        {:allow, priority}

      # Low priority
      true ->
        {:defer, "Low priority application, consider waiting for better opportunities"}
    end
  end

  defp analyze_recent_performance(user_id) do
    # Analyze last 7 days
    seven_days_ago = DateTime.utc_now() |> DateTime.add(-7 * 24 * 3600, :second)

    query = from a in "applications",
      where: a.user_id == ^user_id,
      where: a.submitted_at >= ^seven_days_ago,
      select: a

    applications = Repo.all(query)

    total = length(applications)
    if total > 0 do
      successes = Enum.count(applications, fn a -> a.status in ["interview", "offer", "accepted"] end)
      responses = Enum.count(applications, fn a -> a.status != "pending" end)

      performance_score = (successes / total) * 0.6 + (responses / total) * 0.4

      {:ok, %{
        total_applications: total,
        success_count: successes,
        response_count: responses,
        score: performance_score,
        trend: "stable"  # Could be calculated from time-series data
      }}
    else
      {:ok, %{
        total_applications: 0,
        success_count: 0,
        response_count: 0,
        score: 0.5,
        trend: "unknown"
      }}
    end
  end

  defp compute_adjusted_rate(user_id, performance) do
    # Get current average rate
    {:ok, metrics} = analyze_user_metrics(user_id)

    current_rate = round(metrics.avg_daily_applications)

    # Adjust based on performance
    new_rate = cond do
      performance.score > 0.7 ->
        # Good performance, increase rate
        min(round(current_rate * 1.3), @default_daily_limit)

      performance.score < 0.3 ->
        # Poor performance, decrease rate
        max(round(current_rate * 0.7), 5)

      true ->
        # Stable performance, maintain rate
        current_rate
    end

    {:ok, new_rate}
  end

  defp generate_strategy_rationale(strategy_type, metrics) do
    case strategy_type do
      :aggressive ->
        "High success rate (#{Float.round(metrics.success_rate * 100, 1)}%) justifies aggressive application strategy"

      :conservative ->
        "Low success rate (#{Float.round(metrics.success_rate * 100, 1)}%) requires selective, high-quality applications"

      :balanced ->
        "Moderate performance suggests balanced approach focusing on quality over quantity"
    end
  end

  defp generate_batch_rationale(recommended, tokens, metrics) do
    cond do
      recommended < tokens * 0.5 ->
        "Recommended batch is conservative due to #{if metrics.success_rate < 0.5, do: "low success rate", else: "limited high-quality opportunities"}"

      recommended == tokens ->
        "Use all available tokens for high-quality opportunities"

      true ->
        "Balanced batch size optimizes for success probability and token availability"
    end
  end
end
