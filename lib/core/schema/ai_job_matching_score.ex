defmodule Core.Schema.AiJobMatchingScore do
  @moduledoc """
  Schema for AI-powered job matching scores with multi-factor analysis.

  Stores comprehensive scoring data for job-user matches including:
  - Multi-dimensional skill and experience matching
  - Career growth and culture fit analysis
  - AI-generated recommendations and insights
  - Performance tracking and caching
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :integer

  schema "ai_job_matching_scores" do
    field :user_id, :integer
    field :job_id, :integer
    field :job_external_id, :string

    # Multi-factor scoring components (0.0 to 1.0)
    field :overall_score, :float
    field :skill_match_score, :float
    field :experience_match_score, :float
    field :salary_match_score, :float
    field :location_match_score, :float
    field :company_culture_score, :float
    field :career_growth_score, :float
    field :benefits_score, :float

    # AI analysis results
    field :matching_skills, {:array, :string}, default: []
    field :missing_skills, {:array, :string}, default: []
    field :growth_opportunities, {:array, :string}, default: []
    field :concerns, {:array, :string}, default: []
    field :recommendations, :string

    # Scoring context
    field :cv_id, :integer
    field :model_version, :string
    field :confidence_level, :float
    field :scoring_factors, :map, default: %{}

    # Performance tracking
    field :computation_time_ms, :integer
    field :cached, :boolean, default: false

    timestamps()
  end

  @doc """
  Creates a changeset for AI job matching scores.
  """
  def changeset(score, attrs) do
    score
    |> cast(attrs, [
      :user_id,
      :job_id,
      :job_external_id,
      :overall_score,
      :skill_match_score,
      :experience_match_score,
      :salary_match_score,
      :location_match_score,
      :company_culture_score,
      :career_growth_score,
      :benefits_score,
      :matching_skills,
      :missing_skills,
      :growth_opportunities,
      :concerns,
      :recommendations,
      :cv_id,
      :model_version,
      :confidence_level,
      :scoring_factors,
      :computation_time_ms,
      :cached
    ])
    |> validate_required([
      :user_id,
      :job_id,
      :job_external_id,
      :overall_score,
      :skill_match_score,
      :experience_match_score,
      :salary_match_score,
      :location_match_score,
      :company_culture_score,
      :career_growth_score,
      :benefits_score,
      :model_version
    ])
    |> validate_number(:overall_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:skill_match_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:experience_match_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:salary_match_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:location_match_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:company_culture_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:career_growth_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:benefits_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:confidence_level, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end
end
