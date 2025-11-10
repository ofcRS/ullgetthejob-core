defmodule CoreWeb.API.AIController do
  @moduledoc """
  API controller for AI-powered features.

  Provides endpoints for:
  - Job matching and scoring
  - Success prediction
  - Application orchestration
  - Company research
  - Analytics
  """
  use CoreWeb, :controller
  require Logger
  alias Core.AI
  alias Core.Repo
  import Ecto.Query

  @doc """
  POST /api/ai/orchestrate

  Orchestrates intelligent application workflow for a user.

  Body:
  {
    "user_id": 123,
    "job_ids": [1, 2, 3, ...],
    "options": {
      "min_match_score": 0.5,
      "min_success_probability": 0.4,
      "max_results": 20
    }
  }
  """
  def orchestrate(conn, %{"user_id" => user_id, "job_ids" => job_ids} = params) do
    Logger.info("AI orchestration requested", user_id: user_id, job_count: length(job_ids))

    # Fetch jobs
    query = from j in "jobs", where: j.id in ^job_ids, select: j
    jobs = Repo.all(query)

    opts = parse_options(params["options"] || %{})

    case AI.orchestrate_applications(user_id, jobs, opts) do
      {:ok, result} ->
        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          data: %{
            recommended_jobs: format_recommendations(result.recommended_jobs),
            strategy: result.strategy,
            rate_strategy: format_rate_strategy(result.rate_strategy),
            total_analyzed: result.total_analyzed,
            computation_time_ms: result.computation_time_ms
          }
        })

      {:error, reason} ->
        Logger.error("AI orchestration failed", reason: inspect(reason))
        conn
        |> put_status(:internal_server_error)
        |> json(%{success: false, error: "Orchestration failed: #{inspect(reason)}"})
    end
  end

  @doc """
  POST /api/ai/evaluate-job

  Evaluates a single job for application readiness.

  Body:
  {
    "user_id": 123,
    "job_id": 456
  }
  """
  def evaluate_job(conn, %{"user_id" => user_id, "job_id" => job_id} = params) do
    Logger.info("Job evaluation requested", user_id: user_id, job_id: job_id)

    job = Repo.get("jobs", job_id)

    if job do
      opts = parse_options(params["options"] || %{})

      case AI.evaluate_job(job, user_id, opts) do
        {:ok, evaluation} ->
          conn
          |> put_status(:ok)
          |> json(%{
            success: true,
            data: format_evaluation(evaluation)
          })

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{success: false, error: inspect(reason)})
      end
    else
      conn
      |> put_status(:not_found)
      |> json(%{success: false, error: "Job not found"})
    end
  end

  @doc """
  POST /api/ai/match

  Computes match score for a job and user.
  """
  def compute_match(conn, %{"user_id" => user_id, "job_id" => job_id}) do
    job = Repo.get("jobs", job_id)

    if job do
      case AI.compute_match(job, user_id) do
        {:ok, match_score} ->
          conn
          |> put_status(:ok)
          |> json(%{
            success: true,
            data: format_match_score(match_score)
          })

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{success: false, error: inspect(reason)})
      end
    else
      conn
      |> put_status(:not_found)
      |> json(%{success: false, error: "Job not found"})
    end
  end

  @doc """
  POST /api/ai/predict

  Predicts application success probability.
  """
  def predict_success(conn, %{"user_id" => user_id, "job_id" => job_id}) do
    job = Repo.get("jobs", job_id)

    if job do
      case AI.predict_success(job, user_id) do
        {:ok, prediction} ->
          conn
          |> put_status(:ok)
          |> json(%{
            success: true,
            data: format_prediction(prediction)
          })

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{success: false, error: inspect(reason)})
      end
    else
      conn
      |> put_status(:not_found)
      |> json(%{success: false, error: "Job not found"})
    end
  end

  @doc """
  POST /api/ai/research-company

  Researches a company and returns insights.
  """
  def research_company(conn, %{"company_name" => company_name}) do
    case AI.research_company(company_name) do
      {:ok, research} ->
        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          data: format_company_research(research)
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  @doc """
  GET /api/ai/analytics/realtime

  Gets real-time AI analytics metrics.
  """
  def realtime_metrics(conn, params) do
    opts = [time_window_minutes: params["time_window"] || 60]

    case AI.get_realtime_metrics(opts) do
      {:ok, metrics} ->
        conn
        |> put_status(:ok)
        |> json(%{success: true, data: metrics})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  @doc """
  GET /api/ai/analytics/user/:user_id

  Gets user-specific AI analytics.
  """
  def user_analytics(conn, %{"user_id" => user_id} = params) do
    user_id = String.to_integer(user_id)
    opts = [days_back: params["days_back"] || 30]

    case AI.get_user_analytics(user_id, opts) do
      {:ok, analytics} ->
        conn
        |> put_status(:ok)
        |> json(%{success: true, data: analytics})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  @doc """
  POST /api/ai/record-outcome

  Records actual application outcome for learning.
  """
  def record_outcome(conn, %{"application_id" => application_id, "outcome" => outcome} = params) do
    opts = if params["response_time_hours"] do
      [response_time_hours: params["response_time_hours"]]
    else
      []
    end

    case AI.record_application_outcome(application_id, outcome, opts) do
      {:ok, result} ->
        conn
        |> put_status(:ok)
        |> json(%{success: true, data: result})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  @doc """
  GET /api/ai/health

  AI system health check.
  """
  def health(conn, _params) do
    health_status = AI.health_check()

    conn
    |> put_status(:ok)
    |> json(health_status)
  end

  # Private helper functions

  defp parse_options(opts) do
    [
      min_match_score: opts["min_match_score"] || 0.5,
      min_success_probability: opts["min_success_probability"] || 0.4,
      max_results: opts["max_results"] || 20,
      include_research: opts["include_research"] != false,
      optimize_timing: opts["optimize_timing"] != false
    ]
  end

  defp format_recommendations(jobs) do
    Enum.map(jobs, fn job_data ->
      %{
        job_id: job_data.job.id,
        job_title: job_data.job.title,
        company: job_data.job.company,
        match_score: Float.round(job_data.match_score, 3),
        success_probability: Float.round(job_data.success_probability, 3),
        priority_score: Float.round(job_data.priority_score, 3),
        optimal_time: job_data.prediction.optimal_application_time,
        recommendation: job_data[:recommendation],
        company_research: format_company_research_summary(job_data[:company_research])
      }
    end)
  end

  defp format_evaluation(evaluation) do
    %{
      job: %{
        id: evaluation.job.id,
        title: evaluation.job.title,
        company: evaluation.job.company
      },
      match_score: Float.round(evaluation.match_score.overall_score, 3),
      success_probability: Float.round(evaluation.prediction.success_probability, 3),
      priority_score: Float.round(evaluation.priority_score, 3),
      decision: evaluation.decision,
      timing: evaluation.timing,
      recommendation: evaluation.recommendation,
      company_insights: format_company_research_summary(evaluation.company_research)
    }
  end

  defp format_match_score(score) do
    %{
      overall_score: Float.round(score.overall_score, 3),
      skill_match: Float.round(score.skill_match_score, 3),
      experience_match: Float.round(score.experience_match_score, 3),
      salary_match: Float.round(score.salary_match_score, 3),
      location_match: Float.round(score.location_match_score, 3),
      matching_skills: score.matching_skills,
      missing_skills: score.missing_skills,
      recommendations: score.recommendations,
      confidence: Float.round(score.confidence_level, 3)
    }
  end

  defp format_prediction(prediction) do
    %{
      success_probability: Float.round(prediction.success_probability, 3),
      response_probability: Float.round(prediction.response_probability, 3),
      interview_probability: Float.round(prediction.interview_probability, 3),
      optimal_application_time: prediction.optimal_application_time,
      predicted_response_time_hours: prediction.predicted_response_time_hours,
      competition_level: prediction.competition_level,
      recommendations: prediction.recommendations,
      confidence: Float.round(prediction.confidence_interval, 3)
    }
  end

  defp format_company_research(research) do
    %{
      company_name: research.company_name,
      industry: research.industry,
      description: research.description,
      culture_keywords: research.culture_keywords,
      tech_stack: research.tech_stack,
      values: research.values,
      reputation_score: research.reputation_score && Float.round(research.reputation_score, 3),
      growth_trajectory: research.growth_trajectory,
      hiring_trends: research.hiring_trends,
      last_researched: research.last_researched_at
    }
  end

  defp format_company_research_summary(nil), do: nil
  defp format_company_research_summary(research) do
    %{
      reputation_score: research.reputation_score && Float.round(research.reputation_score, 3),
      culture_keywords: Enum.take(research.culture_keywords, 5),
      tech_stack: Enum.take(research.tech_stack, 10),
      growth_trajectory: research.growth_trajectory
    }
  end

  defp format_rate_strategy(strategy) do
    %{
      strategy_type: strategy.strategy_type,
      recommended_daily_rate: strategy.recommended_daily_rate,
      rationale: strategy.rationale
    }
  end
end
