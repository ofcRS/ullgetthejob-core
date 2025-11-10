defmodule Core.Schema.LearningFeedback do
  @moduledoc """
  Schema for learning feedback to enable continuous model improvement.

  Stores prediction outcomes and actual results for:
  - Model performance analysis
  - Feature importance calculation
  - Retraining data collection
  - A/B testing
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :integer

  schema "learning_feedback" do
    field :feedback_type, :string
    field :model_type, :string
    field :model_version, :string

    # Source references
    field :user_id, :integer
    field :job_id, :integer
    field :application_id, :integer
    field :prediction_id, :binary_id
    field :matching_score_id, :binary_id

    # Prediction vs Reality
    field :predicted_value, :float
    field :actual_value, :float
    field :prediction_error, :float
    field :absolute_error, :float
    field :squared_error, :float

    # Categorical outcomes
    field :predicted_class, :string
    field :actual_class, :string
    field :correct_prediction, :boolean

    # Features and context
    field :feature_vector, :map, default: %{}
    field :feature_importance, :map, default: %{}
    field :context_data, :map, default: %{}
    field :environment, :string

    # Learning metadata
    field :feedback_quality, :float
    field :used_for_training, :boolean, default: false
    field :training_batch_id, :string
    field :model_improvement_impact, :float

    # Time tracking
    field :prediction_timestamp, :utc_datetime
    field :outcome_timestamp, :utc_datetime
    field :feedback_delay_hours, :integer

    timestamps()
  end

  @valid_feedback_types ~w(application_prediction job_matching timing_optimization rate_limit_optimization)
  @valid_model_types ~w(success_predictor matching_engine timing_optimizer rate_limiter)

  def changeset(feedback, attrs) do
    feedback
    |> cast(attrs, [
      :feedback_type,
      :model_type,
      :model_version,
      :user_id,
      :job_id,
      :application_id,
      :prediction_id,
      :matching_score_id,
      :predicted_value,
      :actual_value,
      :prediction_error,
      :absolute_error,
      :squared_error,
      :predicted_class,
      :actual_class,
      :correct_prediction,
      :feature_vector,
      :feature_importance,
      :context_data,
      :environment,
      :feedback_quality,
      :used_for_training,
      :training_batch_id,
      :model_improvement_impact,
      :prediction_timestamp,
      :outcome_timestamp,
      :feedback_delay_hours
    ])
    |> validate_required([
      :feedback_type,
      :model_type,
      :model_version
    ])
    |> validate_inclusion(:feedback_type, @valid_feedback_types)
    |> validate_inclusion(:model_type, @valid_model_types)
    |> validate_number(:feedback_quality, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end
end
