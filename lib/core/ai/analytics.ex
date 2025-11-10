defmodule Core.AI.Analytics do
  @moduledoc """
  Real-time AI analytics engine.

  Provides:
  - Event tracking and logging
  - Real-time metrics computation
  - Performance monitoring
  - User behavior analytics
  - Model effectiveness tracking
  - Dashboards and reporting
  """

  require Logger
  alias Core.Repo
  alias Core.Schema.AiAnalyticsEvent
  alias Core.Broadcaster
  import Ecto.Query

  @doc """
  Tracks an AI analytics event.

  ## Examples

      Analytics.track_event("job_match_computed", %{
        user_id: 1,
        job_id: 123,
        overall_score: 0.85,
        computation_time_ms: 150
      })
  """
  def track_event(event_name, event_data, opts \\ []) do
    timestamp = DateTime.utc_now()

    event_attrs = %{
      event_type: opts[:event_type] || "computation",
      event_category: infer_category(event_name),
      event_name: event_name,
      event_data: event_data,
      event_metadata: opts[:metadata] || %{},
      user_id: event_data[:user_id],
      job_id: event_data[:job_id],
      application_id: event_data[:application_id],
      session_id: opts[:session_id],
      request_id: opts[:request_id],
      model_version: event_data[:model_version],
      prediction_accuracy: event_data[:accuracy] || event_data[:prediction_accuracy],
      confidence_score: event_data[:confidence] || event_data[:confidence_score],
      processing_time_ms: event_data[:computation_time_ms] || event_data[:processing_time_ms],
      metric_value: event_data[:metric_value],
      metric_unit: event_data[:metric_unit],
      dimensions: event_data[:dimensions] || %{},
      event_timestamp: timestamp,
      event_date: DateTime.to_date(timestamp),
      event_hour: timestamp.hour
    }

    case create_event(event_attrs) do
      {:ok, event} ->
        Logger.debug("Analytics event tracked", event_name: event_name)

        # Broadcast to real-time dashboard if needed
        if opts[:broadcast] do
          broadcast_event(event)
        end

        {:ok, event}

      {:error, changeset} ->
        Logger.error("Failed to track analytics event",
          event_name: event_name,
          errors: changeset.errors
        )
        {:error, changeset}
    end
  end

  @doc """
  Tracks multiple events in batch.
  """
  def track_events_batch(events) do
    timestamp = DateTime.utc_now()

    entries = Enum.map(events, fn {event_name, event_data, opts} ->
      %{
        event_type: opts[:event_type] || "computation",
        event_category: infer_category(event_name),
        event_name: event_name,
        event_data: event_data,
        event_metadata: opts[:metadata] || %{},
        user_id: event_data[:user_id],
        job_id: event_data[:job_id],
        event_timestamp: timestamp,
        event_date: DateTime.to_date(timestamp),
        event_hour: timestamp.hour,
        inserted_at: timestamp
      }
    end)

    {count, _} = Repo.insert_all(AiAnalyticsEvent, entries)

    Logger.info("Batch tracked analytics events", count: count)
    {:ok, count}
  end

  @doc """
  Gets real-time metrics for dashboards.
  """
  def get_realtime_metrics(opts \\ []) do
    time_window = opts[:time_window_minutes] || 60
    cutoff = DateTime.utc_now() |> DateTime.add(-time_window * 60, :second)

    query = from e in AiAnalyticsEvent,
      where: e.event_timestamp >= ^cutoff,
      select: e

    events = Repo.all(query)

    metrics = %{
      total_events: length(events),
      events_by_category: count_by_category(events),
      avg_processing_time: avg_processing_time(events),
      model_performance: compute_model_performance(events),
      user_activity: compute_user_activity(events),
      error_rate: compute_error_rate(events)
    }

    {:ok, metrics}
  end

  @doc """
  Gets time-series data for charting.
  """
  def get_timeseries_data(metric_name, opts \\ []) do
    hours_back = opts[:hours_back] || 24
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_back * 3600, :second)

    query = from e in AiAnalyticsEvent,
      where: e.event_timestamp >= ^cutoff,
      where: e.event_name == ^metric_name,
      order_by: [asc: e.event_date, asc: e.event_hour],
      select: %{
        date: e.event_date,
        hour: e.event_hour,
        count: count(e.id),
        avg_value: avg(e.metric_value)
      },
      group_by: [e.event_date, e.event_hour]

    datapoints = Repo.all(query)

    {:ok, %{
      metric_name: metric_name,
      datapoints: datapoints,
      period: "#{hours_back} hours"
    }}
  end

  @doc """
  Computes aggregate statistics for a time period.
  """
  def get_aggregate_stats(category, opts \\ []) do
    days_back = opts[:days_back] || 7
    cutoff = DateTime.utc_now() |> DateTime.add(-days_back * 24 * 3600, :second)

    query = from e in AiAnalyticsEvent,
      where: e.event_timestamp >= ^cutoff,
      where: e.event_category == ^category,
      select: %{
        total_events: count(e.id),
        unique_users: fragment("COUNT(DISTINCT ?)", e.user_id),
        avg_processing_time: avg(e.processing_time_ms),
        avg_confidence: avg(e.confidence_score),
        avg_accuracy: avg(e.prediction_accuracy)
      }

    stats = Repo.one(query) || %{
      total_events: 0,
      unique_users: 0,
      avg_processing_time: 0,
      avg_confidence: 0,
      avg_accuracy: 0
    }

    {:ok, stats}
  end

  @doc """
  Gets user-specific analytics.
  """
  def get_user_analytics(user_id, opts \\ []) do
    days_back = opts[:days_back] || 30
    cutoff = DateTime.utc_now() |> DateTime.add(-days_back * 24 * 3600, :second)

    query = from e in AiAnalyticsEvent,
      where: e.user_id == ^user_id,
      where: e.event_timestamp >= ^cutoff,
      select: e

    events = Repo.all(query)

    analytics = %{
      user_id: user_id,
      total_events: length(events),
      events_by_category: count_by_category(events),
      activity_timeline: build_activity_timeline(events),
      top_events: get_top_events(events, 10),
      model_interactions: count_model_interactions(events)
    }

    {:ok, analytics}
  end

  @doc """
  Gets model performance metrics.
  """
  def get_model_performance(model_type, opts \\ []) do
    days_back = opts[:days_back] || 7
    cutoff = DateTime.utc_now() |> DateTime.add(-days_back * 24 * 3600, :second)

    query = from e in AiAnalyticsEvent,
      where: e.model_version is not nil,
      where: e.event_timestamp >= ^cutoff,
      where: fragment("? LIKE ?", e.event_name, ^"%#{model_type}%"),
      select: %{
        model_version: e.model_version,
        event_count: count(e.id),
        avg_processing_time: avg(e.processing_time_ms),
        avg_confidence: avg(e.confidence_score),
        avg_accuracy: avg(e.prediction_accuracy)
      },
      group_by: e.model_version

    performance_by_version = Repo.all(query)

    {:ok, %{
      model_type: model_type,
      versions: performance_by_version,
      period: "#{days_back} days"
    }}
  end

  @doc """
  Exports analytics data for external analysis.
  """
  def export_analytics(opts \\ []) do
    days_back = opts[:days_back] || 30
    cutoff = DateTime.utc_now() |> DateTime.add(-days_back * 24 * 3600, :second)

    query = from e in AiAnalyticsEvent,
      where: e.event_timestamp >= ^cutoff,
      order_by: [desc: e.event_timestamp]

    query = if limit = opts[:limit], do: limit(query, ^limit), else: query
    query = if category = opts[:category], do: where(query, [e], e.event_category == ^category), else: query

    events = Repo.all(query)

    # Convert to exportable format (CSV-like)
    export_data = Enum.map(events, fn event ->
      %{
        timestamp: event.event_timestamp,
        category: event.event_category,
        event_name: event.event_name,
        user_id: event.user_id,
        processing_time_ms: event.processing_time_ms,
        confidence_score: event.confidence_score,
        prediction_accuracy: event.prediction_accuracy,
        metric_value: event.metric_value,
        data: event.event_data
      }
    end)

    {:ok, export_data}
  end

  # Private functions

  defp create_event(attrs) do
    %AiAnalyticsEvent{}
    |> AiAnalyticsEvent.changeset(attrs)
    |> Repo.insert()
  end

  defp infer_category(event_name) do
    cond do
      String.contains?(event_name, "match") -> "matching"
      String.contains?(event_name, "predict") -> "prediction"
      String.contains?(event_name, "rate") -> "rate_limit"
      String.contains?(event_name, "company") -> "company_research"
      true -> "analytics"
    end
  end

  defp broadcast_event(event) do
    Broadcaster.broadcast_update("analytics:events", %{
      event_name: event.event_name,
      category: event.event_category,
      timestamp: event.event_timestamp,
      data: event.event_data
    })
  end

  defp count_by_category(events) do
    events
    |> Enum.group_by(& &1.event_category)
    |> Enum.map(fn {category, events} -> {category, length(events)} end)
    |> Enum.into(%{})
  end

  defp avg_processing_time(events) do
    times = Enum.reject(events, fn e -> is_nil(e.processing_time_ms) end)

    if length(times) > 0 do
      Enum.sum(Enum.map(times, & &1.processing_time_ms)) / length(times)
    else
      0
    end
  end

  defp compute_model_performance(events) do
    model_events = Enum.reject(events, fn e -> is_nil(e.model_version) end)

    if length(model_events) > 0 do
      accuracy_events = Enum.reject(model_events, fn e -> is_nil(e.prediction_accuracy) end)

      %{
        total_predictions: length(model_events),
        avg_accuracy: if(length(accuracy_events) > 0,
          do: Enum.sum(Enum.map(accuracy_events, & &1.prediction_accuracy)) / length(accuracy_events),
          else: 0),
        avg_confidence: compute_avg(model_events, :confidence_score)
      }
    else
      %{total_predictions: 0, avg_accuracy: 0, avg_confidence: 0}
    end
  end

  defp compute_user_activity(events) do
    users = events
    |> Enum.reject(fn e -> is_nil(e.user_id) end)
    |> Enum.map(& &1.user_id)
    |> Enum.uniq()

    %{
      active_users: length(users),
      events_per_user: if(length(users) > 0, do: length(events) / length(users), else: 0)
    }
  end

  defp compute_error_rate(events) do
    errors = Enum.count(events, fn e -> e.event_type == "failure" end)

    if length(events) > 0 do
      errors / length(events)
    else
      0.0
    end
  end

  defp compute_avg(events, field) do
    valid = Enum.reject(events, fn e -> is_nil(Map.get(e, field)) end)

    if length(valid) > 0 do
      Enum.sum(Enum.map(valid, fn e -> Map.get(e, field) end)) / length(valid)
    else
      0.0
    end
  end

  defp build_activity_timeline(events) do
    events
    |> Enum.group_by(fn e -> {e.event_date, e.event_hour} end)
    |> Enum.map(fn {{date, hour}, events} ->
      %{
        date: date,
        hour: hour,
        event_count: length(events)
      }
    end)
    |> Enum.sort_by(fn m -> {m.date, m.hour} end)
  end

  defp get_top_events(events, limit) do
    events
    |> Enum.group_by(& &1.event_name)
    |> Enum.map(fn {name, events} -> {name, length(events)} end)
    |> Enum.sort_by(fn {_, count} -> -count end)
    |> Enum.take(limit)
    |> Enum.into(%{})
  end

  defp count_model_interactions(events) do
    model_events = Enum.reject(events, fn e -> is_nil(e.model_version) end)

    model_events
    |> Enum.group_by(& &1.model_version)
    |> Enum.map(fn {version, events} -> {version, length(events)} end)
    |> Enum.into(%{})
  end
end
