defmodule Core.Scheduling.Optimizer do
  @moduledoc """
  Optimizes application scheduling to maximize success rates.

  Strategy:
  1. Sort jobs by priority score (highest first)
  2. Space applications 30-60 minutes apart
  3. Target business hours (9 AM - 5 PM local time)
  4. Respect rate limits
  5. Distribute across multiple days if needed
  """

  require Logger
  alias Core.RateLimiter

  @business_hour_start 9   # 9 AM
  @business_hour_end 17    # 5 PM
  @min_gap_minutes 30      # Minimum time between applications
  @max_gap_minutes 60      # Maximum time between applications

  @doc """
  Optimizes schedule for workflow items.

  Returns items with updated :scheduled_time and :priority_score
  """
  def optimize_schedule(items, user_id, timezone \\ "Europe/Moscow") do
    # Get current rate limit status
    rate_status = RateLimiter.get_status(user_id)

    Logger.info("Optimizing schedule for #{length(items)} items, user has #{rate_status.tokens} tokens")

    # Sort by priority score (highest first)
    sorted_items =
      items
      |> Enum.sort_by(& &1.priority_score, :desc)

    # Calculate schedule starting from next available business hour
    now = DateTime.utc_now()
    start_time = next_business_hour(now, timezone)

    # Schedule each item with appropriate gaps
    {scheduled_items, _} =
      sorted_items
      |> Enum.reduce({[], start_time}, fn item, {acc, current_time} ->
        # Calculate gap (random between min and max to appear human)
        gap_minutes = Enum.random(@min_gap_minutes..@max_gap_minutes)

        # Schedule this item
        scheduled_time = current_time

        # Calculate next available time (with gap)
        next_time =
          current_time
          |> DateTime.add(gap_minutes * 60, :second)
          |> ensure_business_hours(timezone)

        updated_item = Map.put(item, :scheduled_time, scheduled_time)

        {[updated_item | acc], next_time}
      end)

    # Return in original priority order
    Enum.reverse(scheduled_items)
  end

  @doc """
  Calculates the next business hour slot.
  If current time is within business hours, returns current time.
  Otherwise, returns next day at 9 AM.
  """
  def next_business_hour(datetime, timezone) do
    # Convert to local timezone
    local_time = datetime_to_timezone(datetime, timezone)
    hour = local_time.hour

    cond do
      # Within business hours - use current time
      hour >= @business_hour_start and hour < @business_hour_end ->
        datetime

      # After business hours - move to next day 9 AM
      hour >= @business_hour_end ->
        datetime
        |> DateTime.add(1, :day)
        |> set_hour(@business_hour_start)

      # Before business hours - move to 9 AM today
      hour < @business_hour_start ->
        datetime
        |> set_hour(@business_hour_start)
    end
  end

  @doc """
  Ensures the scheduled time falls within business hours.
  If not, moves to next business hour.
  """
  def ensure_business_hours(datetime, timezone) do
    local_time = datetime_to_timezone(datetime, timezone)
    hour = local_time.hour

    cond do
      # Within business hours - good to go
      hour >= @business_hour_start and hour < @business_hour_end ->
        datetime

      # Outside business hours - move to next business hour
      true ->
        next_business_hour(datetime, timezone)
    end
  end

  # Helper functions

  defp datetime_to_timezone(datetime, "Europe/Moscow") do
    # Moscow is UTC+3
    DateTime.add(datetime, 3 * 3600, :second)
  end

  defp datetime_to_timezone(datetime, "Europe/London") do
    # London is UTC+0 (or +1 in summer, but we'll use +0 for simplicity)
    datetime
  end

  defp datetime_to_timezone(datetime, "America/New_York") do
    # New York is UTC-5 (or -4 in summer)
    DateTime.add(datetime, -5 * 3600, :second)
  end

  defp datetime_to_timezone(datetime, _timezone) do
    # Default to UTC
    datetime
  end

  defp set_hour(datetime, hour) do
    %{datetime | hour: hour, minute: 0, second: 0}
  end

  @doc """
  Calculates estimated completion time for workflow based on schedule.
  """
  def estimate_completion(items, user_id) do
    rate_status = RateLimiter.get_status(user_id)

    scheduled_items =
      items
      |> Enum.filter(&(&1.status in ["pending", "ready"]))

    if Enum.empty?(scheduled_items) do
      %{
        estimated_completion: DateTime.utc_now(),
        items_count: 0,
        days_needed: 0,
        tokens_available: rate_status.tokens
      }
    else
      # Calculate based on rate limit: 8 applications/hour
      hours_needed = Float.ceil(length(scheduled_items) / 8.0)
      days_needed = Float.ceil(hours_needed / 8.0)  # 8 working hours per day

      completion_time =
        DateTime.utc_now()
        |> DateTime.add(round(hours_needed * 3600), :second)

      %{
        estimated_completion: completion_time,
        items_count: length(scheduled_items),
        hours_needed: hours_needed,
        days_needed: days_needed,
        tokens_available: rate_status.tokens
      }
    end
  end
end
