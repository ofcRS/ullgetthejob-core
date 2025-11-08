defmodule Core.Workers.BatchCustomizeWorker do
  @moduledoc """
  Oban worker for batch customizing CVs for multiple jobs.
  Processes jobs in workflow and prepares them for application.
  """

  use Oban.Worker,
    queue: :customization,
    max_attempts: 3,
    priority: 1,
    tags: ["customization", "batch"]

  require Logger
  alias Core.{Repo, Workflow, Broadcaster}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "workflow_id" => workflow_id,
          "user_id" => user_id
        }
      }) do
    Logger.info("Starting batch customization for workflow #{workflow_id}")

    # Get all pending items
    items = Workflow.get_workflow_items(workflow_id)
    total = length(items)

    # Broadcast start
    Broadcaster.broadcast_customization_progress(user_id, %{
      workflow_id: workflow_id,
      completed: 0,
      total: total,
      status: "started"
    })

    # Process each item
    items
    |> Enum.with_index(1)
    |> Enum.each(fn {item, index} ->
      try do
        # Update status
        Workflow.update_status(item.id, "customizing")

        # Call Node BFF to customize (assuming BFF has customization endpoint)
        case customize_job(item, user_id) do
          {:ok, _result} ->
            Workflow.update_status(item.id, "ready")
            Logger.info("Customized job #{index}/#{total} for workflow #{workflow_id}")

            # Broadcast progress
            Broadcaster.broadcast_customization_progress(user_id, %{
              workflow_id: workflow_id,
              completed: index,
              total: total,
              current_job: item.job_external_id
            })

          {:error, reason} ->
            Logger.error("Failed to customize job #{item.id}: #{inspect(reason)}")
            Workflow.update_status(item.id, "failed", error: to_string(reason))
        end
      rescue
        error ->
          Logger.error("Exception customizing job #{item.id}: #{inspect(error)}")
          Workflow.update_status(item.id, "failed", error: Exception.message(error))
      end

      # Rate limit: 1 per second to avoid overwhelming AI API
      Process.sleep(1000)
    end)

    # Broadcast completion
    progress = Workflow.get_progress(workflow_id)

    Broadcaster.broadcast_customization_progress(user_id, %{
      workflow_id: workflow_id,
      completed: total,
      total: total,
      status: "completed",
      stats: progress
    })

    Logger.info("Batch customization completed for workflow #{workflow_id}")
    {:ok, %{workflow_id: workflow_id, processed: total}}
  end

  defp customize_job(queue_item, user_id) do
    # TODO: Call Node BFF /api/cv/customize endpoint
    # For now, return success
    {:ok, %{customized: true}}
  end
end
