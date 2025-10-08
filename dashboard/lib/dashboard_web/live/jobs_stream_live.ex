defmodule DashboardWeb.JobsStreamLive do
  use DashboardWeb, :live_view
  require Logger

  alias DashboardWeb.Presence
  alias Dashboard.RateLimiter

  @presence_topic "jobs:presence"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Dashboard.PubSub, "jobs:stream")
      Phoenix.PubSub.subscribe(Dashboard.PubSub, @presence_topic)

      # Track this user's presence
      {:ok, _} =
        Presence.track(self(), @presence_topic, socket.id, %{
          joined_at: System.system_time(:second)
        })

      :timer.send_interval(1000, self(), :tick)
    end

    socket =
      assign(socket,
        jobs: [],
        all_jobs: [],
        selected_jobs: MapSet.new(),
        stats: %{
          current_rps: 0,
          total_fetched: 0,
          fetch_count: 0,
          last_duration: 0
        },
        max_job_displayed: 100,
        auto_scroll: true,
        status: :idle,
        elapsed_seconds: 0,
        viewer_count: 0,
        rate_limiter_stats: %{},
        filters: %{
          title: "",
          company: "",
          area: ""
        }
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
    {:noreply, assign(socket, jobs: [], selected_jobs: MapSet.new())}
  end

  @impl true
  def handle_event("toggle_job_selection", %{"job_id" => job_id}, socket) do
    selected_jobs = socket.assigns.selected_jobs

    new_selection =
      if MapSet.member?(selected_jobs, job_id) do
        MapSet.delete(selected_jobs, job_id)
      else
        MapSet.put(selected_jobs, job_id)
      end

    {:noreply, assign(socket, selected_jobs: new_selection)}
  end

  @impl true
  def handle_event("apply_to_selected", _params, socket) do
    selected = MapSet.to_list(socket.assigns.selected_jobs)

    if Enum.empty?(selected) do
      {:noreply, put_flash(socket, :error, "Please select at least one job")}
    else
      # Get the active CV
      case Dashboard.CVs.get_active_cv() do
        nil ->
          {:noreply, put_flash(socket, :error, "Please upload a CV first")}

        cv ->
          # For now, just redirect to the CV editor with the first selected job
          first_job_id = List.first(selected)
          {:noreply, push_navigate(socket, to: ~p"/cvs/#{cv.id}/edit?job_id=#{first_job_id}")}
      end
    end
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    all_job_ids = Enum.map(socket.assigns.jobs, & &1.id) |> MapSet.new()
    {:noreply, assign(socket, selected_jobs: all_job_ids)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_jobs: MapSet.new())}
  end

  @impl true
  def handle_event("toggle_scroll", _params, socket) do
    {:noreply, assign(socket, auto_scroll: !socket.assigns.auto_scroll)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = %{
      title: params["title"] || "",
      company: params["company"] || "",
      area: params["area"] || ""
    }

    filtered_jobs = apply_filters(socket.assigns.all_jobs, filters)

    socket =
      assign(socket,
        filters: filters,
        jobs: Enum.take(filtered_jobs, socket.assigns.max_job_displayed)
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    filters = %{title: "", company: "", area: ""}

    socket =
      assign(socket,
        filters: filters,
        jobs: Enum.take(socket.assigns.all_jobs, socket.assigns.max_job_displayed)
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_jobs, new_jobs, stats}, socket) do
    all_jobs = new_jobs ++ socket.assigns.all_jobs

    # Apply current filters
    filtered_jobs = apply_filters(all_jobs, socket.assigns.filters)
    jobs = Enum.take(filtered_jobs, socket.assigns.max_job_displayed)

    updated_stats =
      Map.merge(socket.assigns.stats, stats)
      |> Map.update(:total_fetched, length(new_jobs), &(&1 + length(new_jobs)))
      |> Map.update(:fetch_count, 1, &(&1 + 1))
      |> Map.put(:last_duration, stats.duration)

    socket =
      assign(socket,
        all_jobs: all_jobs,
        jobs: jobs,
        stats: updated_stats,
        status: :idle
      )

    {:noreply, push_event(socket, "new-jobs", %{count: length(new_jobs)})}
  end

  @impl true
  def handle_info(:tick, socket) do
    # Update viewer count
    viewer_count =
      Presence.list(@presence_topic)
      |> map_size()

    # Get rate limiter stats
    rate_limiter_stats = RateLimiter.get_stats()

    socket =
      assign(socket,
        elapsed_seconds: socket.assigns.elapsed_seconds + 1,
        viewer_count: viewer_count,
        rate_limiter_stats: rate_limiter_stats
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "presence_diff"}, socket) do
    viewer_count =
      Presence.list(@presence_topic)
      |> map_size()

    {:noreply, assign(socket, viewer_count: viewer_count)}
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

  defp apply_filters(jobs, %{title: "", company: "", area: ""}), do: jobs

  defp apply_filters(jobs, filters) do
    jobs
    |> filter_by_title(filters.title)
    |> filter_by_company(filters.company)
    |> filter_by_area(filters.area)
  end

  defp filter_by_title(jobs, ""), do: jobs

  defp filter_by_title(jobs, title) do
    title_lower = String.downcase(title)

    Enum.filter(jobs, fn job ->
      job.title
      |> to_string()
      |> String.downcase()
      |> String.contains?(title_lower)
    end)
  end

  defp filter_by_company(jobs, ""), do: jobs

  defp filter_by_company(jobs, company) do
    company_lower = String.downcase(company)

    Enum.filter(jobs, fn job ->
      job.company
      |> to_string()
      |> String.downcase()
      |> String.contains?(company_lower)
    end)
  end

  defp filter_by_area(jobs, ""), do: jobs

  defp filter_by_area(jobs, area) do
    area_lower = String.downcase(area)

    Enum.filter(jobs, fn job ->
      job.area
      |> to_string()
      |> String.downcase()
      |> String.contains?(area_lower)
    end)
  end
end
