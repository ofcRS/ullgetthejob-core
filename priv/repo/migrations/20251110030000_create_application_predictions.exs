defmodule Core.Repo.Migrations.CreateApplicationPredictions do
  use Ecto.Migration

  def change do
    create table(:application_predictions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, :integer, null: false
      add :job_id, :integer, null: false
      add :job_external_id, :string, null: false
      add :application_id, :integer

      # Success prediction
      add :success_probability, :float, null: false
      add :response_probability, :float, null: false
      add :interview_probability, :float, null: false
      add :offer_probability, :float, null: false

      # Timing predictions
      add :predicted_response_time_hours, :integer
      add :predicted_review_time_hours, :integer
      add :optimal_application_time, :utc_datetime
      add :competition_level, :string

      # Prediction factors
      add :user_profile_strength, :float
      add :job_match_quality, :float
      add :timing_score, :float
      add :market_demand_score, :float
      add :company_responsiveness_score, :float

      # Historical context
      add :similar_applications_count, :integer
      add :similar_success_rate, :float
      add :user_historical_success_rate, :float

      # AI model info
      add :model_version, :string, null: false
      add :confidence_interval, :float
      add :prediction_factors, :map, default: %{}
      add :recommendations, :text

      # Actual outcomes (for learning)
      add :actual_outcome, :string
      add :actual_response_time_hours, :integer
      add :outcome_recorded_at, :utc_datetime
      add :prediction_accuracy, :float

      # Performance
      add :computation_time_ms, :integer

      timestamps()
    end

    create index(:application_predictions, [:user_id, :job_id])
    create index(:application_predictions, [:job_external_id])
    create index(:application_predictions, [:application_id])
    create index(:application_predictions, [:success_probability])
    create index(:application_predictions, [:optimal_application_time])
    create index(:application_predictions, [:actual_outcome])
    create index(:application_predictions, [:inserted_at])
  end
end
