defmodule Core.Workers.AutoApplyWorker do
  @moduledoc """
  Oban worker for auto-applying to jobs with rate limiting.
  Processes one job at a time, respecting HH.ru API limits.
  """

  use Oban.Worker,
    queue: :applications,
    max_attempts: 5,
    priority: 2,
    tags: ["applications", "auto_apply"]

  require Logger
  alias Core.{Repo, Workflow, RateLimiter, HH, Broadcaster}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "workflow_id" => workflow_id,
          "user_id" => user_id
        },
        attempt: attempt
      }) do
    Logger.info("Processing auto-apply for workflow #{workflow_id}, attempt #{attempt}")

    # Get next ready item
    case get_next_ready_item(workflow_id) do
      nil ->
        Logger.info("No more ready items for workflow #{workflow_id}")
        {:ok, %{status: "completed"}}

      item ->
        process_item(item, user_id, workflow_id)
    end
  end

  defp get_next_ready_item(workflow_id) do
    Workflow.get_ready_items(workflow_id)
    |> List.first()
  end

  defp process_item(item, user_id, workflow_id) do
    # Check rate limit
    case RateLimiter.check_rate_limit(user_id, :application) do
      {:ok, remaining} ->
        Logger.info("Rate limit check passed. Tokens remaining: #{remaining}")
        submit_application(item, user_id, workflow_id)

      {:error, :rate_limited, next_refill} ->
        Logger.warn("Rate limited for user #{user_id}. Next refill: #{next_refill}")
        handle_rate_limit(item, user_id, workflow_id, next_refill)
    end
  end

  defp submit_application(item, user_id, workflow_id) do
    # Update status
    Workflow.update_status(item.id, "submitting")

    # Broadcast progress
    progress = Workflow.get_progress(workflow_id)
    Broadcaster.broadcast_application_progress(user_id, %{
      workflow_id: workflow_id,
      completed: progress.submitted,
      total: progress.submitted + progress.pending + progress.ready,
      current_job: item.job_external_id
    })

    # Get access token
    with {:ok, access_token} <- HH.OAuth.get_valid_token(user_id),
         # Get or create resume
         {:ok, resume_id} <- get_resume_for_item(item, access_token),
         # Publish resume
         :ok <- HH.Client.publish_resume(access_token, resume_id),
         # Submit application
         {:ok, negotiation_id} <- HH.Client.submit_application(
           access_token,
           item.job_external_id,
           resume_id,
           get_cover_letter(item)
         ) do

      # Success!
      Workflow.update_status(item.id, "submitted")

      Logger.info("Successfully submitted application for job #{item.job_external_id}")

      # Broadcast success
      Broadcaster.broadcast_application_completed(user_id, %{
        job_title: get_in(item.payload, ["jobTitle"]) || "Job",
        company: get_in(item.payload, ["company"]) || "Company",
        status: "success",
        negotiation_id: negotiation_id
      })

      # Schedule next job in workflow
      schedule_next_job(workflow_id, user_id)

      {:ok, %{submitted: item.id}}
    else
      {:error, reason} ->
        Logger.error("Failed to submit application: #{inspect(reason)}")

        Workflow.update_status(item.id, "failed", error: inspect(reason))

        # Broadcast failure
        Broadcaster.broadcast_application_completed(user_id, %{
          job_title: get_in(item.payload, ["jobTitle"]) || "Job",
          company: get_in(item.payload, ["company"]) || "Company",
          status: "failed",
          error_message: inspect(reason)
        })

        # Continue to next job despite failure
        schedule_next_job(workflow_id, user_id)

        {:ok, %{failed: item.id}}
    end
  end

  defp handle_rate_limit(item, user_id, workflow_id, next_refill) do
    # Update item to rate_limited status
    Workflow.update_status(item.id, "rate_limited", next_run_at: next_refill)

    # Broadcast rate limit status
    rate_status = RateLimiter.get_status(user_id)
    Broadcaster.broadcast_rate_limit_update(user_id, %{
      tokens: rate_status.tokens,
      capacity: rate_status.capacity,
      next_refill: next_refill,
      can_apply: false
    })

    # Calculate delay until next refill (add 10 seconds buffer)
    delay_seconds = DateTime.diff(next_refill, DateTime.utc_now()) + 10

    # Schedule retry
    %{
      "workflow_id" => workflow_id,
      "user_id" => user_id
    }
    |> Core.Workers.AutoApplyWorker.new(schedule_in: delay_seconds)
    |> Oban.insert()

    Logger.info("Scheduled retry in #{delay_seconds} seconds")
    {:ok, %{rate_limited: true, retry_in: delay_seconds}}
  end

  defp schedule_next_job(workflow_id, user_id) do
    # Check if there are more jobs
    case get_next_ready_item(workflow_id) do
      nil ->
        Logger.info("No more jobs in workflow #{workflow_id}")
        :ok

      _next_item ->
        # Schedule immediately (rate limit will handle throttling)
        %{
          "workflow_id" => workflow_id,
          "user_id" => user_id
        }
        |> Core.Workers.AutoApplyWorker.new()
        |> Oban.insert()

        Logger.info("Scheduled next job for workflow #{workflow_id}")
        :ok
    end
  end

  defp get_resume_for_item(item, access_token) do
    # TODO: Get customized CV from database and create HH resume
    # For now, use default resume creation
    HH.Client.get_or_create_resume(access_token, %{})
  end

  defp get_cover_letter(item) do
    # TODO: Get from custom_cvs table
    get_in(item.payload, ["coverLetter"]) || "Dear Hiring Manager, I am interested in this position."
  end
end
