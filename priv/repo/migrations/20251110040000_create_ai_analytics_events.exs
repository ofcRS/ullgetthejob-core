defmodule Core.Repo.Migrations.CreateAiAnalyticsEvents do
  use Ecto.Migration

  def change do
    create table(:ai_analytics_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, :integer
      add :event_type, :string, null: false
      add :event_category, :string, null: false

      # Event data
      add :event_name, :string, null: false
      add :event_data, :map, default: %{}
      add :event_metadata, :map, default: %{}

      # Context
      add :session_id, :string
      add :request_id, :string
      add :job_id, :integer
      add :application_id, :integer

      # AI metrics
      add :model_version, :string
      add :prediction_accuracy, :float
      add :confidence_score, :float
      add :processing_time_ms, :integer

      # Aggregation support
      add :metric_value, :float
      add :metric_unit, :string
      add :dimensions, :map, default: %{}

      # Time-series support
      add :event_timestamp, :utc_datetime, null: false
      add :event_date, :date, null: false
      add :event_hour, :integer

      timestamps(updated_at: false)
    end

    create index(:ai_analytics_events, [:event_type])
    create index(:ai_analytics_events, [:event_category])
    create index(:ai_analytics_events, [:user_id, :event_timestamp])
    create index(:ai_analytics_events, [:event_date, :event_hour])
    create index(:ai_analytics_events, [:session_id])
    create index(:ai_analytics_events, [:job_id])
    create index(:ai_analytics_events, [:application_id])
    create index(:ai_analytics_events, [:event_timestamp])
  end
end
