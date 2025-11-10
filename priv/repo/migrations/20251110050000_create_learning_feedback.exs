defmodule Core.Repo.Migrations.CreateLearningFeedback do
  use Ecto.Migration

  def change do
    create table(:learning_feedback, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :feedback_type, :string, null: false
      add :model_type, :string, null: false
      add :model_version, :string, null: false

      # Source references
      add :user_id, :integer
      add :job_id, :integer
      add :application_id, :integer
      add :prediction_id, :uuid
      add :matching_score_id, :uuid

      # Prediction vs Reality
      add :predicted_value, :float
      add :actual_value, :float
      add :prediction_error, :float
      add :absolute_error, :float
      add :squared_error, :float

      # Categorical outcomes
      add :predicted_class, :string
      add :actual_class, :string
      add :correct_prediction, :boolean

      # Features used for prediction
      add :feature_vector, :map, default: %{}
      add :feature_importance, :map, default: %{}

      # Context
      add :context_data, :map, default: %{}
      add :environment, :string

      # Learning metadata
      add :feedback_quality, :float
      add :used_for_training, :boolean, default: false
      add :training_batch_id, :string
      add :model_improvement_impact, :float

      # Time tracking
      add :prediction_timestamp, :utc_datetime
      add :outcome_timestamp, :utc_datetime
      add :feedback_delay_hours, :integer

      timestamps()
    end

    create index(:learning_feedback, [:feedback_type])
    create index(:learning_feedback, [:model_type, :model_version])
    create index(:learning_feedback, [:user_id])
    create index(:learning_feedback, [:prediction_id])
    create index(:learning_feedback, [:used_for_training])
    create index(:learning_feedback, [:correct_prediction])
    create index(:learning_feedback, [:outcome_timestamp])
    create index(:learning_feedback, [:inserted_at])
  end
end
