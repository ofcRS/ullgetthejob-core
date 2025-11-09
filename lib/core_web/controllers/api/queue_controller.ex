defmodule CoreWeb.Api.QueueController do
  use CoreWeb, :controller
  require Logger

  alias Core.{Workflow, Workers}

  plug :verify_orchestrator_secret

  @doc """
  Start batch customization for workflow
  """
  def batch_customize(conn, %{"workflow_id" => workflow_id, "user_id" => user_id}) do
    Logger.info("Starting batch customization: workflow=#{workflow_id} user=#{user_id}")

    # Queue Oban job
    case %{
      "workflow_id" => workflow_id,
      "user_id" => user_id
    }
    |> Workers.BatchCustomizeWorker.new()
    |> Oban.insert() do
      {:ok, %Oban.Job{id: job_id}} ->
        json(conn, %{
          success: true,
          job_id: job_id,
          message: "Batch customization started"
        })

      {:error, reason} ->
        Logger.error("Failed to start batch customization: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to start batch customization"
        })
    end
  end

  @doc """
  Start auto-apply workflow
  """
  def start_workflow(conn, %{"workflow_id" => workflow_id, "user_id" => user_id}) do
    Logger.info("Starting auto-apply workflow: workflow=#{workflow_id} user=#{user_id}")

    # Calculate estimated completion
    estimate = Workflow.estimate_completion(workflow_id, user_id)

    # Queue first auto-apply job
    case %{
      "workflow_id" => workflow_id,
      "user_id" => user_id
    }
    |> Workers.AutoApplyWorker.new()
    |> Oban.insert() do
      {:ok, %Oban.Job{id: job_id}} ->
        json(conn, %{
          success: true,
          job_id: job_id,
          workflow_id: workflow_id,
          estimatedCompletion: estimate.estimated_completion,
          pending_count: estimate.pending_count,
          hours_needed: estimate.hours_needed,
          message: "Auto-apply workflow started"
        })

      {:error, reason} ->
        Logger.error("Failed to start workflow: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to start workflow"
        })
    end
  end

  @doc """
  Get workflow progress
  """
  def progress(conn, %{"workflow_id" => workflow_id}) do
    progress = Workflow.get_progress(workflow_id)

    json(conn, %{
      success: true,
      progress: progress
    })
  end

  defp verify_orchestrator_secret(conn, _opts) do
    secret = conn |> get_req_header("x-core-secret") |> List.first()
    expected = System.get_env("ORCHESTRATOR_SECRET")

    if secret == expected do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Unauthorized"})
      |> halt()
    end
  end
end
