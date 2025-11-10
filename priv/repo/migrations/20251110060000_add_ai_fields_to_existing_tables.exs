defmodule Core.Repo.Migrations.AddAiFieldsToExistingTables do
  use Ecto.Migration

  def change do
    # Add AI fields to jobs table
    alter table(:jobs) do
      add :ai_enriched, :boolean, default: false
      add :ai_enrichment_data, :map, default: %{}
      add :extracted_skills, {:array, :string}, default: []
      add :extracted_requirements, {:array, :string}, default: []
      add :seniority_level, :string
      add :remote_work_type, :string
      add :job_category, :string
      add :difficulty_score, :float
      add :competition_estimate, :string
      add :salary_competitive_score, :float
      add :ai_summary, :text
      add :enriched_at, :utc_datetime
    end

    # Add AI fields to applications table
    alter table(:applications) do
      add :ai_customized, :boolean, default: false
      add :customization_score, :float
      add :application_strategy, :string
      add :success_prediction_id, :uuid
      add :matching_score_id, :uuid
      add :optimal_timing, :boolean, default: false
      add :ai_recommendations_followed, {:array, :string}, default: []
    end

    # Create indexes for AI fields
    create index(:jobs, [:ai_enriched])
    create index(:jobs, [:seniority_level])
    create index(:jobs, [:job_category])
    create index(:jobs, [:enriched_at])

    create index(:applications, [:ai_customized])
    create index(:applications, [:success_prediction_id])
    create index(:applications, [:matching_score_id])
  end
end
