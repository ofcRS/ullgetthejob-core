defmodule Core.AI.Prediction.TimingOptimizer do
  @moduledoc """
  Intelligent application timing optimization.

  Analyzes optimal timing for job applications based on:
  - Job posting freshness
  - Company response patterns
  - Day of week and time of day
  - Historical success rates by timing
  - Competition level at different times
  """

  require Logger
  alias Core.Repo
  import Ecto.Query

  @doc """
  Computes optimal application timing for a job.
  """
  def compute_optimal_timing(job, features) do
    now = DateTime.utc_now()

    # Analyze timing factors
    freshness_score = analyze_job_freshness(job, now)
    time_of_day_score = analyze_time_of_day(now)
    day_of_week_score = analyze_day_of_week(now)
    company_patterns = analyze_company_patterns(job.company)

    # Compute overall timing score
    timing_score =
      freshness_score * 0.4 +
      time_of_day_score * 0.3 +
      day_of_week_score * 0.2 +
      company_patterns.score * 0.1

    # Determine optimal application time
    optimal_time = if timing_score > 0.7 do
      # Good time to apply now
      now
    else
      # Calculate better time
      calculate_better_time(now, company_patterns)
    end

    # Predict response times
    predicted_response_time = predict_response_time(job, company_patterns)
    predicted_review_time = predict_review_time(job, company_patterns)

    {:ok, %{
      optimal_time: optimal_time,
      timing_score: timing_score,
      predicted_response_time: predicted_response_time,
      predicted_review_time: predicted_review_time,
      competition_level: estimate_competition(job, now),
      recommendations: generate_timing_recommendations(timing_score, optimal_time, now),
      factors: %{
        freshness: freshness_score,
        time_of_day: time_of_day_score,
        day_of_week: day_of_week_score,
        company_pattern: company_patterns.score
      }
    }}
  end

  # Job freshness analysis
  defp analyze_job_freshness(job, now) do
    posted_at = job.fetched_at || job.inserted_at
    age_hours = DateTime.diff(now, posted_at, :hour)

    # Best to apply early but not immediately
    # Sweet spot is 4-48 hours after posting
    cond do
      age_hours < 4 -> 0.7         # Too early, may not be reviewed yet
      age_hours < 24 -> 1.0        # Perfect timing
      age_hours < 48 -> 0.9        # Still excellent
      age_hours < 168 -> 0.6       # Within a week - okay
      age_hours < 336 -> 0.4       # 2 weeks - getting old
      true -> 0.2                   # Stale listing
    end
  end

  # Time of day analysis
  defp analyze_time_of_day(datetime) do
    hour = datetime.hour

    # Business hours in Moscow (HH.ru timezone)
    # Peak review times: 9-11 AM, 2-4 PM
    cond do
      hour >= 9 && hour < 11 -> 1.0   # Morning peak
      hour >= 14 && hour < 16 -> 0.9  # Afternoon peak
      hour >= 11 && hour < 14 -> 0.7  # Lunch time
      hour >= 16 && hour < 18 -> 0.6  # Late afternoon
      hour >= 8 && hour < 9 -> 0.5    # Early morning
      hour >= 18 && hour < 20 -> 0.4  # Evening
      true -> 0.2                      # Off hours
    end
  end

  # Day of week analysis
  defp analyze_day_of_week(datetime) do
    day = Date.day_of_week(datetime)

    # Tuesday-Thursday are best, avoid weekends
    case day do
      2 -> 1.0  # Tuesday
      3 -> 1.0  # Wednesday
      4 -> 0.9  # Thursday
      1 -> 0.7  # Monday
      5 -> 0.6  # Friday
      6 -> 0.2  # Saturday
      7 -> 0.1  # Sunday
    end
  end

  # Company response pattern analysis
  defp analyze_company_patterns(company_name) do
    query = from a in "applications",
      join: j in "jobs", on: a.job_id == j.id,
      where: j.company == ^company_name,
      where: not is_nil(a.status),
      where: a.status != "pending",
      select: %{
        submitted_at: a.submitted_at,
        response_time_hours: fragment(
          "EXTRACT(EPOCH FROM (? - ?)) / 3600",
          a.updated_at,
          a.submitted_at
        ),
        day_of_week: fragment("EXTRACT(DOW FROM ?)", a.submitted_at),
        hour: fragment("EXTRACT(HOUR FROM ?)", a.submitted_at)
      },
      limit: 100

    results = Repo.all(query)

    if length(results) > 5 do
      analyze_patterns(results)
    else
      # Default pattern for unknown companies
      %{
        score: 0.5,
        best_days: [2, 3, 4],
        best_hours: [9, 10, 14, 15],
        avg_response_time: 72
      }
    end
  end

  defp analyze_patterns(results) do
    # Find days with highest response rates
    day_stats = results
      |> Enum.group_by(& &1.day_of_week)
      |> Enum.map(fn {day, apps} ->
        {day, length(apps)}
      end)
      |> Enum.sort_by(fn {_, count} -> -count end)
      |> Enum.take(3)
      |> Enum.map(fn {day, _} -> day end)

    # Find hours with fastest responses
    hour_stats = results
      |> Enum.reject(fn r -> is_nil(r.response_time_hours) end)
      |> Enum.group_by(& &1.hour)
      |> Enum.map(fn {hour, apps} ->
        avg_time = Enum.sum(Enum.map(apps, & &1.response_time_hours)) / length(apps)
        {hour, avg_time}
      end)
      |> Enum.sort_by(fn {_, time} -> time end)
      |> Enum.take(4)
      |> Enum.map(fn {hour, _} -> hour end)

    # Average response time
    valid_times = Enum.reject(results, fn r -> is_nil(r.response_time_hours) end)
    avg_response = if length(valid_times) > 0 do
      Enum.sum(Enum.map(valid_times, & &1.response_time_hours)) / length(valid_times)
    else
      72
    end

    %{
      score: 0.7,  # Higher score if we have data
      best_days: day_stats,
      best_hours: hour_stats,
      avg_response_time: round(avg_response)
    }
  end

  # Calculate better application time
  defp calculate_better_time(now, patterns) do
    # Find next optimal day
    current_day = Date.day_of_week(now)
    best_days = patterns.best_days

    next_best_day = Enum.find(best_days, fn day -> day >= current_day end) ||
      Enum.at(best_days, 0)

    days_to_add = if next_best_day >= current_day do
      next_best_day - current_day
    else
      7 - current_day + next_best_day
    end

    # Find next optimal hour
    best_hour = Enum.at(patterns.best_hours, 0) || 10

    # Calculate next optimal datetime
    now
    |> DateTime.add(days_to_add * 24 * 3600, :second)
    |> DateTime.to_date()
    |> DateTime.new!(Time.new!(best_hour, 0, 0))
    |> elem(1)
  end

  # Response time prediction
  defp predict_response_time(job, company_patterns) do
    base_time = company_patterns.avg_response_time

    # Adjust based on job characteristics
    multiplier = cond do
      String.contains?(String.downcase(job.title), "senior") -> 1.3
      String.contains?(String.downcase(job.title), "lead") -> 1.5
      String.contains?(String.downcase(job.title), "junior") -> 0.8
      true -> 1.0
    end

    round(base_time * multiplier)
  end

  defp predict_review_time(job, company_patterns) do
    # Review time is typically 30-50% of response time
    round(predict_response_time(job, company_patterns) * 0.4)
  end

  # Competition estimation
  defp estimate_competition(job, now) do
    age_hours = DateTime.diff(now, job.inserted_at, :hour)

    # Fresh jobs have high competition
    cond do
      age_hours < 24 -> "high"
      age_hours < 72 -> "medium"
      true -> "low"
    end
  end

  # Timing recommendations
  defp generate_timing_recommendations(timing_score, optimal_time, now) do
    cond do
      timing_score >= 0.8 ->
        "Excellent time to apply now. High probability of quick review."

      timing_score >= 0.6 ->
        "Good time to apply. Consider applying within the next few hours."

      DateTime.compare(optimal_time, now) == :gt ->
        delay_hours = DateTime.diff(optimal_time, now, :hour)
        "Consider waiting #{delay_hours} hours for optimal timing (#{format_datetime(optimal_time)})."

      true ->
        "Timing is suboptimal but acceptable. Apply if urgent, otherwise wait for business hours."
    end
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end
end
