defmodule Core.Schema.ApplicationPrediction do
  @moduledoc """
  Schema for AI-powered application success predictions.

  Stores predictions for application outcomes, timing, and success factors.
  Used for continuous learning as actual outcomes are recorded.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :integer

  schema "application_predictions" do
    field :user_id, :integer
    field :job_id, :integer
    field :job_external_id, :string
    field :application_id, :integer

    # Success predictions (0.0 to 1.0)
    field :success_probability, :float
    field :response_probability, :float
    field :interview_probability, :float
    field :offer_probability, :float

    # Timing predictions
    field :predicted_response_time_hours, :integer
    field :predicted_review_time_hours, :integer
    field :optimal_application_time, :utc_datetime
    field :competition_level, :string

    # Prediction factors (0.0 to 1.0)
    field :user_profile_strength, :float
    field :job_match_quality, :float
    field :timing_score, :float
    field :market_demand_score, :float
    field :company_responsiveness_score, :float

    # Historical context
    field :similar_applications_count, :integer
    field :similar_success_rate, :float
    field :user_historical_success_rate, :float

    # AI model metadata
    field :model_version, :string
    field :confidence_interval, :float
    field :prediction_factors, :map, default: %{}
    field :recommendations, :string

    # Actual outcomes (for learning)
    field :actual_outcome, :string
    field :actual_response_time_hours, :integer
    field :outcome_recorded_at, :utc_datetime
    field :prediction_accuracy, :float

    # Performance
    field :computation_time_ms, :integer

    timestamps()
  end

  @valid_outcomes ~w(pending rejected interview offer accepted)

  def changeset(prediction, attrs) do
    prediction
    |> cast(attrs, [
      :user_id,
      :job_id,
      :job_external_id,
      :application_id,
      :success_probability,
      :response_probability,
      :interview_probability,
      :offer_probability,
      :predicted_response_time_hours,
      :predicted_review_time_hours,
      :optimal_application_time,
      :competition_level,
      :user_profile_strength,
      :job_match_quality,
      :timing_score,
      :market_demand_score,
      :company_responsiveness_score,
      :similar_applications_count,
      :similar_success_rate,
      :user_historical_success_rate,
      :model_version,
      :confidence_interval,
      :prediction_factors,
      :recommendations,
      :actual_outcome,
      :actual_response_time_hours,
      :outcome_recorded_at,
      :prediction_accuracy,
      :computation_time_ms
    ])
    |> validate_required([
      :user_id,
      :job_id,
      :job_external_id,
      :success_probability,
      :response_probability,
      :interview_probability,
      :offer_probability,
      :model_version
    ])
    |> validate_number(:success_probability, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:response_probability, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:interview_probability, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:offer_probability, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_inclusion(:actual_outcome, @valid_outcomes)
  end

  def record_outcome_changeset(prediction, outcome, response_time_hours) do
    accuracy = calculate_accuracy(prediction.success_probability, outcome)

    prediction
    |> cast(%{
      actual_outcome: outcome,
      actual_response_time_hours: response_time_hours,
      outcome_recorded_at: DateTime.utc_now(),
      prediction_accuracy: accuracy
    }, [:actual_outcome, :actual_response_time_hours, :outcome_recorded_at, :prediction_accuracy])
    |> validate_required([:actual_outcome, :outcome_recorded_at])
  end

  defp calculate_accuracy(predicted_probability, actual_outcome) do
    # Convert outcome to binary success (1.0) or failure (0.0)
    actual_value = if actual_outcome in ["offer", "accepted"], do: 1.0, else: 0.0

    # Calculate accuracy as 1 - absolute error
    1.0 - abs(predicted_probability - actual_value)
  end
end
