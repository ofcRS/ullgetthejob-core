defmodule Core.AI.Learning.FeedbackCollector do
  @moduledoc """
  Collects feedback from predictions vs actual outcomes for continuous learning.

  Tracks:
  - Prediction accuracy
  - Feature importance
  - Model performance metrics
  - Training data for model improvement
  """

  require Logger
  alias Core.Repo
  alias Core.Schema.LearningFeedback
  alias Core.AI.Analytics

  @doc """
  Collects feedback from an application prediction with recorded outcome.
  """
  def collect_prediction_feedback(prediction) do
    if prediction.actual_outcome do
      Logger.info("Collecting learning feedback",
        prediction_id: prediction.id,
        accuracy: prediction.prediction_accuracy
      )

      feedback_attrs = %{
        feedback_type: "application_prediction",
        model_type: "success_predictor",
        model_version: prediction.model_version,
        user_id: prediction.user_id,
        job_id: prediction.job_id,
        application_id: prediction.application_id,
        prediction_id: prediction.id,

        # Prediction vs reality
        predicted_value: prediction.success_probability,
        actual_value: outcome_to_value(prediction.actual_outcome),
        prediction_error: calculate_error(prediction),
        absolute_error: abs(calculate_error(prediction)),
        squared_error: :math.pow(calculate_error(prediction), 2),

        # Categorical outcome
        predicted_class: classify_probability(prediction.success_probability),
        actual_class: prediction.actual_outcome,
        correct_prediction: correct_classification?(prediction),

        # Features used
        feature_vector: extract_feature_vector(prediction),

        # Context
        context_data: %{
          job_external_id: prediction.job_external_id,
          confidence_interval: prediction.confidence_interval,
          prediction_factors: prediction.prediction_factors
        },
        environment: "production",

        # Timing
        prediction_timestamp: prediction.inserted_at,
        outcome_timestamp: prediction.outcome_recorded_at,
        feedback_delay_hours: DateTime.diff(
          prediction.outcome_recorded_at,
          prediction.inserted_at,
          :hour
        ),

        # Quality
        feedback_quality: assess_feedback_quality(prediction),
        used_for_training: false
      }

      case create_feedback(feedback_attrs) do
        {:ok, feedback} ->
          # Track analytics event
          Analytics.track_event("learning_feedback_collected", %{
            model_type: "success_predictor",
            accuracy: prediction.prediction_accuracy,
            correct: feedback.correct_prediction
          })

          # Check if we should trigger model retraining
          check_retraining_threshold()

          {:ok, feedback}

        {:error, reason} ->
          Logger.error("Failed to collect feedback",
            prediction_id: prediction.id,
            reason: inspect(reason)
          )
          {:error, reason}
      end
    else
      {:error, :no_outcome_recorded}
    end
  end

  @doc """
  Collects feedback from matching scores when application outcome is known.
  """
  def collect_matching_feedback(matching_score, application) do
    if application.status do
      feedback_attrs = %{
        feedback_type: "job_matching",
        model_type: "matching_engine",
        model_version: matching_score.model_version,
        user_id: matching_score.user_id,
        job_id: matching_score.job_id,
        application_id: application.id,
        matching_score_id: matching_score.id,

        # Score vs outcome
        predicted_value: matching_score.overall_score,
        actual_value: outcome_to_value(application.status),
        prediction_error: matching_score.overall_score - outcome_to_value(application.status),
        absolute_error: abs(matching_score.overall_score - outcome_to_value(application.status)),
        squared_error: :math.pow(matching_score.overall_score - outcome_to_value(application.status), 2),

        # Features
        feature_vector: %{
          skill_match: matching_score.skill_match_score,
          experience_match: matching_score.experience_match_score,
          salary_match: matching_score.salary_match_score,
          location_match: matching_score.location_match_score,
          culture_match: matching_score.company_culture_score,
          growth_match: matching_score.career_growth_score,
          benefits_match: matching_score.benefits_score
        },

        context_data: %{
          matching_skills: matching_score.matching_skills,
          missing_skills: matching_score.missing_skills,
          confidence: matching_score.confidence_level
        },

        prediction_timestamp: matching_score.inserted_at,
        outcome_timestamp: application.updated_at,
        feedback_quality: 0.8,
        used_for_training: false
      }

      create_feedback(feedback_attrs)
    else
      {:error, :no_outcome_available}
    end
  end

  @doc """
  Gets learning feedback for model analysis and retraining.
  """
  def get_training_data(model_type, opts \\ []) do
    import Ecto.Query

    query = from f in LearningFeedback,
      where: f.model_type == ^model_type,
      where: f.feedback_quality >= 0.5,
      order_by: [desc: f.inserted_at]

    query = if limit = opts[:limit], do: limit(query, ^limit), else: query
    query = if opts[:unused_only], do: where(query, [f], f.used_for_training == false), else: query

    Repo.all(query)
  end

  @doc """
  Marks feedback as used for training.
  """
  def mark_used_for_training(feedback_ids, batch_id) do
    import Ecto.Query

    from(f in LearningFeedback, where: f.id in ^feedback_ids)
    |> Repo.update_all(set: [used_for_training: true, training_batch_id: batch_id])
  end

  @doc """
  Computes model performance metrics from collected feedback.
  """
  def compute_performance_metrics(model_type, time_window_days \\ 30) do
    import Ecto.Query

    cutoff = DateTime.utc_now() |> DateTime.add(-time_window_days * 24 * 3600, :second)

    query = from f in LearningFeedback,
      where: f.model_type == ^model_type,
      where: f.inserted_at >= ^cutoff,
      select: f

    feedback = Repo.all(query)

    if length(feedback) > 0 do
      %{
        total_predictions: length(feedback),
        mean_absolute_error: calculate_mae(feedback),
        root_mean_squared_error: calculate_rmse(feedback),
        accuracy: calculate_accuracy(feedback),
        precision: calculate_precision(feedback),
        recall: calculate_recall(feedback),
        f1_score: calculate_f1(feedback)
      }
    else
      nil
    end
  end

  # Private functions

  defp create_feedback(attrs) do
    %LearningFeedback{}
    |> LearningFeedback.changeset(attrs)
    |> Repo.insert()
  end

  defp outcome_to_value(outcome) do
    case outcome do
      "offer" -> 1.0
      "accepted" -> 1.0
      "interview" -> 0.7
      "rejected" -> 0.0
      "pending" -> 0.5
      _ -> 0.0
    end
  end

  defp calculate_error(prediction) do
    prediction.success_probability - outcome_to_value(prediction.actual_outcome)
  end

  defp classify_probability(prob) do
    cond do
      prob >= 0.7 -> "high_success"
      prob >= 0.4 -> "medium_success"
      true -> "low_success"
    end
  end

  defp correct_classification?(prediction) do
    predicted_class = classify_probability(prediction.success_probability)
    actual_value = outcome_to_value(prediction.actual_outcome)

    case predicted_class do
      "high_success" -> actual_value >= 0.7
      "medium_success" -> actual_value >= 0.4 && actual_value < 0.7
      "low_success" -> actual_value < 0.4
    end
  end

  defp extract_feature_vector(prediction) do
    %{
      user_profile_strength: prediction.user_profile_strength,
      job_match_quality: prediction.job_match_quality,
      timing_score: prediction.timing_score,
      market_demand_score: prediction.market_demand_score,
      company_responsiveness_score: prediction.company_responsiveness_score,
      similar_success_rate: prediction.similar_success_rate,
      user_historical_success_rate: prediction.user_historical_success_rate
    }
  end

  defp assess_feedback_quality(prediction) do
    # Quality based on confidence and data completeness
    factors = [
      prediction.confidence_interval > 0.6,
      not is_nil(prediction.actual_response_time_hours),
      prediction.similar_applications_count > 5,
      prediction.user_historical_success_rate > 0
    ]

    Enum.count(factors, & &1) / length(factors)
  end

  defp check_retraining_threshold do
    # Check if we have enough new feedback to trigger retraining
    import Ecto.Query

    unused_count = from(f in LearningFeedback,
      where: f.used_for_training == false,
      where: f.feedback_quality >= 0.7,
      select: count(f.id)
    )
    |> Repo.one()

    if unused_count >= 100 do
      Logger.info("Retraining threshold reached", unused_feedback_count: unused_count)
      # TODO: Trigger model retraining process
      # This could send a message to a training service or queue a job
    end
  end

  # Metric calculations

  defp calculate_mae(feedback) do
    errors = Enum.map(feedback, & &1.absolute_error)
    Enum.sum(errors) / length(errors)
  end

  defp calculate_rmse(feedback) do
    squared_errors = Enum.map(feedback, & &1.squared_error)
    mean_squared_error = Enum.sum(squared_errors) / length(squared_errors)
    :math.sqrt(mean_squared_error)
  end

  defp calculate_accuracy(feedback) do
    correct = Enum.count(feedback, & &1.correct_prediction)
    correct / length(feedback)
  end

  defp calculate_precision(feedback) do
    # Precision for "high_success" predictions
    high_success_predictions = Enum.filter(feedback, fn f ->
      f.predicted_class == "high_success"
    end)

    if length(high_success_predictions) > 0 do
      true_positives = Enum.count(high_success_predictions, fn f ->
        outcome_to_value(f.actual_class) >= 0.7
      end)
      true_positives / length(high_success_predictions)
    else
      0.0
    end
  end

  defp calculate_recall(feedback) do
    # Recall for actual successes
    actual_successes = Enum.filter(feedback, fn f ->
      outcome_to_value(f.actual_class) >= 0.7
    end)

    if length(actual_successes) > 0 do
      correctly_predicted = Enum.count(actual_successes, fn f ->
        f.predicted_class == "high_success"
      end)
      correctly_predicted / length(actual_successes)
    else
      0.0
    end
  end

  defp calculate_f1(feedback) do
    precision = calculate_precision(feedback)
    recall = calculate_recall(feedback)

    if precision + recall > 0 do
      2 * (precision * recall) / (precision + recall)
    else
      0.0
    end
  end
end
