defmodule Core.AI do
  @moduledoc """
  Main interface for AI-powered features.

  This module provides a unified API for all AI capabilities:

  ## Job Matching
  - Multi-factor scoring based on skills, experience, salary, location, culture, and growth potential
  - Semantic skill matching with confidence levels
  - Detailed recommendations and insights

  ## Success Prediction
  - Predicts application success probability
  - Estimates response times and interview likelihood
  - Optimal timing recommendations
  - Continuous learning from outcomes

  ## Rate Limit Optimization
  - Intelligent token allocation
  - Priority-based application decisions
  - Dynamic rate adjustment based on performance

  ## Company Research
  - Automated company intelligence gathering
  - Culture and values analysis
  - Technology stack identification
  - Hiring trends and reputation scoring

  ## Analytics
  - Real-time performance monitoring
  - User behavior tracking
  - Model effectiveness metrics
  - Dashboard data and exports

  ## Orchestration
  - End-to-end intelligent application workflow
  - Combines all AI features for optimal results
  - Automated decision making and prioritization
  """

  # Job Matching
  defdelegate compute_match(job, user_id, opts \\ []), to: Core.AI.Matching.Engine, as: :compute_match
  defdelegate batch_compute_matches(jobs, user_id, opts \\ []), to: Core.AI.Matching.Engine, as: :batch_compute_matches
  defdelegate get_top_matches(user_id, limit \\ 20, opts \\ []), to: Core.AI.Matching.Engine, as: :get_top_matches

  # Success Prediction
  defdelegate predict_success(job, user_id, opts \\ []), to: Core.AI.Prediction.Engine, as: :predict_success
  defdelegate batch_predict(jobs, user_id, opts \\ []), to: Core.AI.Prediction.Engine, as: :batch_predict
  defdelegate record_outcome(prediction_id, outcome, response_time_hours \\ nil), to: Core.AI.Prediction.Engine, as: :record_outcome
  defdelegate get_user_predictions(user_id, opts \\ []), to: Core.AI.Prediction.Engine, as: :get_user_predictions

  # Rate Limit Optimization
  defdelegate compute_optimal_rate(user_id, available_jobs, opts \\ []), to: Core.AI.RateLimit.Optimizer, as: :compute_optimal_rate
  defdelegate should_allow_application?(user_id, job, opts \\ []), to: Core.AI.RateLimit.Optimizer, as: :should_allow_application?
  defdelegate recommend_batch_size(user_id, available_jobs), to: Core.AI.RateLimit.Optimizer, as: :recommend_batch_size
  defdelegate adjust_rate_limits(user_id), to: Core.AI.RateLimit.Optimizer, as: :adjust_rate_limits

  # Company Research
  defdelegate research_company(company_name, opts \\ []), to: Core.AI.Company.ResearchEngine, as: :research_company
  defdelegate batch_research_companies(company_names, opts \\ []), to: Core.AI.Company.ResearchEngine, as: :batch_research_companies
  defdelegate get_company_research(company_name), to: Core.AI.Company.ResearchEngine, as: :get_company_research

  # Analytics
  defdelegate track_event(event_name, event_data, opts \\ []), to: Core.AI.Analytics, as: :track_event
  defdelegate get_realtime_metrics(opts \\ []), to: Core.AI.Analytics, as: :get_realtime_metrics
  defdelegate get_timeseries_data(metric_name, opts \\ []), to: Core.AI.Analytics, as: :get_timeseries_data
  defdelegate get_user_analytics(user_id, opts \\ []), to: Core.AI.Analytics, as: :get_user_analytics
  defdelegate get_model_performance(model_type, opts \\ []), to: Core.AI.Analytics, as: :get_model_performance

  # Orchestration (Main Entry Point)
  defdelegate orchestrate_applications(user_id, available_jobs, opts \\ []), to: Core.AI.Orchestrator, as: :orchestrate_applications
  defdelegate evaluate_job(job, user_id, opts \\ []), to: Core.AI.Orchestrator, as: :evaluate_job
  defdelegate optimize_batch(user_id, available_jobs, opts \\ []), to: Core.AI.Orchestrator, as: :optimize_batch
  defdelegate record_application_outcome(application_id, outcome, opts \\ []), to: Core.AI.Orchestrator, as: :record_application_outcome

  @doc """
  Gets comprehensive AI insights for a job.

  Convenience function that combines matching, prediction, and company research.
  """
  def get_job_insights(job, user_id, opts \\ []) do
    Core.AI.Orchestrator.evaluate_job(job, user_id, opts)
  end

  @doc """
  Quick health check for AI systems.
  """
  def health_check do
    %{
      status: "healthy",
      components: %{
        matching_engine: "operational",
        prediction_engine: "operational",
        rate_optimizer: "operational",
        company_research: "operational",
        analytics: "operational",
        orchestrator: "operational"
      },
      version: "1.0.0",
      timestamp: DateTime.utc_now()
    }
  end
end
