defmodule Core.Repo.Migrations.CreateAiJobMatchingScores do
  use Ecto.Migration

  def change do
    create table(:ai_job_matching_scores, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, :integer, null: false
      add :job_id, :integer, null: false
      add :job_external_id, :string, null: false

      # Multi-factor scoring components
      add :overall_score, :float, null: false
      add :skill_match_score, :float, null: false
      add :experience_match_score, :float, null: false
      add :salary_match_score, :float, null: false
      add :location_match_score, :float, null: false
      add :company_culture_score, :float, null: false
      add :career_growth_score, :float, null: false
      add :benefits_score, :float, null: false

      # AI analysis metadata
      add :matching_skills, {:array, :string}, default: []
      add :missing_skills, {:array, :string}, default: []
      add :growth_opportunities, {:array, :string}, default: []
      add :concerns, {:array, :string}, default: []
      add :recommendations, :text

      # Scoring context
      add :cv_id, :integer
      add :model_version, :string, null: false
      add :confidence_level, :float
      add :scoring_factors, :map, default: %{}

      # Performance tracking
      add :computation_time_ms, :integer
      add :cached, :boolean, default: false

      timestamps()
    end

    create index(:ai_job_matching_scores, [:user_id, :job_id])
    create index(:ai_job_matching_scores, [:job_external_id])
    create index(:ai_job_matching_scores, [:overall_score])
    create index(:ai_job_matching_scores, [:user_id, :overall_score])
    create index(:ai_job_matching_scores, [:inserted_at])
  end
end
