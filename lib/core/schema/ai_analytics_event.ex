defmodule Core.Schema.AiAnalyticsEvent do
  @moduledoc """
  Schema for real-time AI analytics events.

  Tracks all AI-related events and metrics for:
  - Performance monitoring
  - Usage analytics
  - Model effectiveness
  - User behavior
  - System health
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :integer

  schema "ai_analytics_events" do
    field :user_id, :integer
    field :event_type, :string
    field :event_category, :string
    field :event_name, :string
    field :event_data, :map, default: %{}
    field :event_metadata, :map, default: %{}

    # Context
    field :session_id, :string
    field :request_id, :string
    field :job_id, :integer
    field :application_id, :integer

    # AI metrics
    field :model_version, :string
    field :prediction_accuracy, :float
    field :confidence_score, :float
    field :processing_time_ms, :integer

    # Aggregation support
    field :metric_value, :float
    field :metric_unit, :string
    field :dimensions, :map, default: %{}

    # Time-series support
    field :event_timestamp, :utc_datetime
    field :event_date, :date
    field :event_hour, :integer

    timestamps(updated_at: false)
  end

  @valid_categories ~w(matching prediction rate_limit company_research analytics)
  @valid_types ~w(computation success failure user_action model_performance)

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :user_id,
      :event_type,
      :event_category,
      :event_name,
      :event_data,
      :event_metadata,
      :session_id,
      :request_id,
      :job_id,
      :application_id,
      :model_version,
      :prediction_accuracy,
      :confidence_score,
      :processing_time_ms,
      :metric_value,
      :metric_unit,
      :dimensions,
      :event_timestamp,
      :event_date,
      :event_hour
    ])
    |> validate_required([:event_type, :event_category, :event_name, :event_timestamp, :event_date, :event_hour])
    |> validate_inclusion(:event_category, @valid_categories)
    |> validate_inclusion(:event_type, @valid_types)
  end
end
