defmodule Core.Workers.SmartOrchestrator do
  @moduledoc """
  Smart orchestration worker that optimizes application scheduling.

  Features:
  - Calculates priority scores for jobs (match quality, freshness, urgency)
  - Schedules applications during business hours (9 AM - 5 PM)
  - Spaces applications 30-60 minutes apart to appear human
  - Respects rate limits and adjusts schedule accordingly
  """

  use Oban.Worker,
    queue: :orchestration,
    max_attempts: 3,
    priority: 0,
    tags: ["orchestration", "scheduling"]

  require Logger
  alias Core.{Repo, Workflow, Scheduling.Optimizer}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "workflow_id" => workflow_id,
          "user_id" => user_id
        }
      }) do
    Logger.info("Starting smart orchestration for workflow #{workflow_id}")

    # Get all pending and ready items
    items = Workflow.get_workflow_items(workflow_id)

    # Filter items that need scheduling
    schedulable_items =
      items
      |> Enum.filter(&schedulable?/1)

    if Enum.empty?(schedulable_items) do
      Logger.info("No items to schedule for workflow #{workflow_id}")
      {:ok, %{scheduled: 0}}
    else
      # Calculate priority scores
      scored_items = Enum.map(schedulable_items, &score_item/1)

      # Optimize schedule (time + priority)
      optimized_items = Optimizer.optimize_schedule(scored_items, user_id)

      # Update items with new schedule and priority
      update_results =
        optimized_items
        |> Enum.map(&update_item_schedule/1)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> length()

      Logger.info("Smart orchestration completed: #{update_results}/#{length(schedulable_items)} items scheduled")

      {:ok, %{scheduled: update_results, total: length(schedulable_items)}}
    end
  end

  defp schedulable?(item) do
    item.status in ["pending", "ready", "rate_limited"]
  end

  defp score_item(item) do
    base_score = 50

    # Priority scoring
    match_score = get_in(item.payload, ["matchScore"]) || get_in(item.payload, [:matchScore]) || 0
    freshness_score = calculate_freshness_score(item.inserted_at)
    urgency_score = calculate_urgency_score(item.payload)

    total_priority = base_score + match_score + freshness_score + urgency_score

    Logger.debug("Item #{item.id} priority: #{total_priority} (match:#{match_score} fresh:#{freshness_score} urgent:#{urgency_score})")

    Map.put(item, :priority_score, total_priority)
  end

  defp calculate_freshness_score(inserted_at) when is_struct(inserted_at, NaiveDateTime) do
    now = NaiveDateTime.utc_now()
    hours_old = NaiveDateTime.diff(now, inserted_at, :hour)

    cond do
      hours_old < 24 -> 20   # Very fresh (posted today)
      hours_old < 48 -> 10   # Fresh (posted yesterday)
      hours_old < 72 -> 5    # Moderately fresh
      true -> 0              # Older posting
    end
  end

  defp calculate_freshness_score(_), do: 0

  defp calculate_urgency_score(payload) do
    # Check for urgency indicators in job description
    job_title = get_in(payload, ["jobTitle"]) || get_in(payload, [:jobTitle]) || ""
    description = get_in(payload, ["description"]) || get_in(payload, [:description]) || ""

    text = String.downcase("#{job_title} #{description}")

    cond do
      String.contains?(text, ["urgent", "срочно", "asap", "немедленно"]) -> 15
      String.contains?(text, ["soon", "quickly", "скоро"]) -> 8
      true -> 0
    end
  end

  defp update_item_schedule(item) do
    changeset =
      item
      |> Ecto.Changeset.change(%{
        priority: item.priority_score || item.priority || 0,
        next_run_at: item.scheduled_time || item.next_run_at,
        updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })

    Repo.update(changeset)
  end
end
