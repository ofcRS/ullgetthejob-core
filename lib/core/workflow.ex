defmodule Core.Workflow do
  @moduledoc """
  Context for managing application workflows.
  Tracks multi-job application campaigns with status and progress.
  """

  import Ecto.Query
  alias Core.Repo
  alias Core.Schema.ApplicationQueue

  @doc """
  Create workflow items for multiple jobs
  """
  def create_workflow_items(workflow_id, user_id, cv_id, job_external_ids) do
    items = Enum.map(job_external_ids, fn job_external_id ->
      %{
        workflow_id: workflow_id,
        user_id: user_id,
        cv_id: cv_id,
        job_external_id: job_external_id,
        status: "pending",
        priority: 0,
        attempts: 0,
        next_run_at: DateTime.utc_now(),
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      }
    end)

    Repo.insert_all(ApplicationQueue, items)
    {:ok, length(items)}
  end

  @doc """
  Get all items for a workflow
  """
  def get_workflow_items(workflow_id) do
    ApplicationQueue
    |> where([q], q.workflow_id == ^workflow_id)
    |> order_by([q], [asc: q.priority, asc: q.next_run_at])
    |> Repo.all()
  end

  @doc """
  Get pending items ready to process
  """
  def get_ready_items(workflow_id) do
    now = DateTime.utc_now()

    ApplicationQueue
    |> where([q], q.workflow_id == ^workflow_id)
    |> where([q], q.status in ["pending", "ready"])
    |> where([q], q.next_run_at <= ^now)
    |> order_by([q], [asc: q.priority, asc: q.next_run_at])
    |> Repo.all()
  end

  @doc """
  Update item status
  """
  def update_status(item_id, status, opts \\ []) do
    changeset =
      ApplicationQueue
      |> Repo.get!(item_id)
      |> Ecto.Changeset.change(%{
        status: status,
        updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })

    changeset =
      if error = opts[:error] do
        Ecto.Changeset.change(changeset, %{
          last_error: error,
          attempts: (changeset.data.attempts || 0) + 1
        })
      else
        changeset
      end

    changeset =
      if next_run_at = opts[:next_run_at] do
        Ecto.Changeset.change(changeset, %{next_run_at: next_run_at})
      else
        changeset
      end

    Repo.update(changeset)
  end

  @doc """
  Get workflow progress statistics
  """
  def get_progress(workflow_id) do
    query = from q in ApplicationQueue,
      where: q.workflow_id == ^workflow_id,
      group_by: q.status,
      select: {q.status, count(q.id)}

    results = Repo.all(query)

    %{
      pending: get_count(results, "pending"),
      customizing: get_count(results, "customizing"),
      ready: get_count(results, "ready"),
      submitting: get_count(results, "submitting"),
      submitted: get_count(results, "submitted"),
      failed: get_count(results, "failed"),
      rate_limited: get_count(results, "rate_limited")
    }
  end

  defp get_count(results, status) do
    Enum.find_value(results, 0, fn {s, count} ->
      if s == status, do: count
    end)
  end

  @doc """
  Calculate estimated completion time based on rate limits
  """
  def estimate_completion(workflow_id, user_id) do
    items = get_workflow_items(workflow_id)
    pending_count = Enum.count(items, &(&1.status in ["pending", "ready"]))

    # Get current rate limit status
    rate_status = Core.RateLimiter.get_status(user_id)

    # Calculate hours needed (8 applications per hour)
    hours_needed = Float.ceil(pending_count / 8.0)

    # Add current time
    completion = DateTime.utc_now() |> DateTime.add(round(hours_needed * 3600), :second)

    %{
      pending_count: pending_count,
      hours_needed: hours_needed,
      estimated_completion: completion,
      current_tokens: rate_status.tokens
    }
  end

  @doc """
  Get high-priority items for a workflow (sorted by priority score DESC)
  """
  def get_high_priority_items(workflow_id, limit \\ 10) do
    ApplicationQueue
    |> where([q], q.workflow_id == ^workflow_id)
    |> where([q], q.status in ["pending", "ready"])
    |> order_by([q], [desc: q.priority, asc: q.next_run_at])
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Update priority for an item
  """
  def update_priority(item_id, priority) do
    ApplicationQueue
    |> Repo.get!(item_id)
    |> Ecto.Changeset.change(%{
      priority: priority,
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Bulk update schedule for items (used by orchestrator)
  """
  def bulk_update_schedule(updates) when is_list(updates) do
    Enum.map(updates, fn %{id: id, next_run_at: next_run_at, priority: priority} ->
      ApplicationQueue
      |> Repo.get!(id)
      |> Ecto.Changeset.change(%{
        next_run_at: next_run_at,
        priority: priority,
        updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })
      |> Repo.update()
    end)
  end

  @doc """
  Get workflow statistics including scheduling info
  """
  def get_workflow_stats(workflow_id) do
    items = get_workflow_items(workflow_id)
    progress = get_progress(workflow_id)

    # Calculate average priority
    avg_priority =
      items
      |> Enum.map(& &1.priority)
      |> Enum.sum()
      |> case do
        0 -> 0
        sum -> div(sum, length(items))
      end

    # Find next scheduled time
    next_scheduled =
      items
      |> Enum.filter(&(&1.status in ["pending", "ready"]))
      |> Enum.map(& &1.next_run_at)
      |> Enum.min(fn -> DateTime.utc_now() end, DateTime)

    Map.merge(progress, %{
      total_items: length(items),
      avg_priority: avg_priority,
      next_scheduled: next_scheduled
    })
  end
end
