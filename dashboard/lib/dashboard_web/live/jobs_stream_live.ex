defmodule DashboardWeb.JobsStreamLive do
  use DashboardWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Dashboard.PubSub, "jobs:stream")

      :timer.send_interval(1000, self(), :tick)
    end

    socket =
      assign(socket,
        jobs: [],
        stats: %{
          current_rps: 0,
          total_fetched: 0,
          fetch_count: 0,
          last_duration: 0
        },
        max_job_displayed: 100,
        auto_scroll: true,
        status: :idle,
        elapsed_seconds: 0
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("fetch_now", _params, socket) do
    Dashboard.Jobs.Fetcher.fetch_jobs_now()
    {:noreply, assign(socket, status: :fetching)}
  end

  @impl true
  def handle_event("clear_jobs", _params, socket) do
    {:noreply, assign(socket, jobs: [])}
  end

  @impl true
  def handle_event("toggle_scroll", _params, socket) do
    {:noreply, assign(socket, auto_scroll: !socket.assigns.auto_scroll)}
  end

  @impl true
  def handle_info({:new_jobs, new_jobs, stats}, socket) do
    jobs =
      (new_jobs ++ socket.assigns.jobs)
      |> Enum.take(socket.assigns.max_job_displayed)

    updated_stats =
      Map.merge(socket.assigns.stats, stats)
      |> Map.update(:total_fetched, length(new_jobs), &(&1 + length(new_jobs)))
      |> Map.update(:fetch_count, 1, &(&1 + 1))
      |> Map.put(:last_duration, stats.duration)

    socket =
      assign(socket,
        jobs: jobs,
        stats: updated_stats,
        status: :idle
      )

    {:noreply, push_event(socket, "new-jobs", %{count: length(new_jobs)})}
  end

  @impl true
  def handle_info(:tick, socket) do
    socket = assign(socket, elapsed_seconds: socket.assigns.elapsed_seconds + 1)
    {:noreply, socket}
  end

  defp format_time(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _} ->
        datetime
        |> DateTime.shift_zone!("Etc/UTC")
        |> Calendar.strftime("%H:%M:%S")

      _ ->
        "Unknown"
    end
  end

  defp format_time(_), do: "Unknown"

  defp format_elapsed(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    :io_lib.format("~2..0B:~2..0B:~2..0B", [hours, minutes, secs])
    |> IO.iodata_to_binary()
  end

  defp calculate_avg_rps(%{total_fetched: _total, elapsed_seconds: 0}), do: "0"

  defp calculate_avg_rps(%{total_fetched: total, fetch_count: count}) when count > 0 do
    Float.round(total / count, 2) |> to_string()
  end

  defp calculate_avg_rps(_), do: "0"

  defp calculate_avg_jobs(%{total_fetched: total, fetch_count: count}) when count > 0 do
    Float.round(total / count, 1) |> to_string()
  end

  defp calculate_avg_jobs(_), do: "0"
end
