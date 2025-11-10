defmodule Core.Schema.CompanyResearch do
  @moduledoc """
  Schema for AI-powered company research data.

  Stores comprehensive company information gathered and analyzed by AI:
  - Company profile and basics
  - Culture and values
  - Technology stack
  - Employee satisfaction metrics
  - Market position and health
  - Hiring trends
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "company_research" do
    field :company_name, :string
    field :company_id_external, :string

    # Company information
    field :industry, :string
    field :size, :string
    field :founded_year, :integer
    field :website, :string
    field :description, :string

    # AI-gathered insights
    field :culture_keywords, {:array, :string}, default: []
    field :tech_stack, {:array, :string}, default: []
    field :benefits, {:array, :string}, default: []
    field :values, {:array, :string}, default: []
    field :recent_news, {:array, :map}, default: []

    # AI analysis scores
    field :reputation_score, :float
    field :employee_satisfaction_score, :float
    field :growth_trajectory, :string
    field :hiring_trends, :map, default: %{}
    field :salary_ranges, :map, default: %{}

    # Market intelligence
    field :competitors, {:array, :string}, default: []
    field :market_position, :string
    field :financial_health, :string

    # Metadata
    field :data_sources, {:array, :string}, default: []
    field :last_researched_at, :utc_datetime
    field :research_quality_score, :float
    field :research_completeness, :float
    field :ai_model_version, :string

    # Cache management
    field :cache_valid_until, :utc_datetime
    field :stale, :boolean, default: false

    timestamps()
  end

  def changeset(research, attrs) do
    research
    |> cast(attrs, [
      :company_name,
      :company_id_external,
      :industry,
      :size,
      :founded_year,
      :website,
      :description,
      :culture_keywords,
      :tech_stack,
      :benefits,
      :values,
      :recent_news,
      :reputation_score,
      :employee_satisfaction_score,
      :growth_trajectory,
      :hiring_trends,
      :salary_ranges,
      :competitors,
      :market_position,
      :financial_health,
      :data_sources,
      :last_researched_at,
      :research_quality_score,
      :research_completeness,
      :ai_model_version,
      :cache_valid_until,
      :stale
    ])
    |> validate_required([:company_name])
    |> validate_number(:reputation_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:employee_satisfaction_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:research_quality_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:research_completeness, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> unique_constraint(:company_name)
  end
end
