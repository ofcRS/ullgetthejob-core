defmodule Core.Repo.Migrations.CreateCompanyResearch do
  use Ecto.Migration

  def change do
    create table(:company_research, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :company_name, :string, null: false
      add :company_id_external, :string

      # Company information
      add :industry, :string
      add :size, :string
      add :founded_year, :integer
      add :website, :string
      add :description, :text

      # AI-gathered insights
      add :culture_keywords, {:array, :string}, default: []
      add :tech_stack, {:array, :string}, default: []
      add :benefits, {:array, :string}, default: []
      add :values, {:array, :string}, default: []
      add :recent_news, {:array, :map}, default: []

      # AI analysis
      add :reputation_score, :float
      add :employee_satisfaction_score, :float
      add :growth_trajectory, :string
      add :hiring_trends, :map, default: %{}
      add :salary_ranges, :map, default: %{}

      # Market intelligence
      add :competitors, {:array, :string}, default: []
      add :market_position, :string
      add :financial_health, :string

      # Metadata
      add :data_sources, {:array, :string}, default: []
      add :last_researched_at, :utc_datetime
      add :research_quality_score, :float
      add :research_completeness, :float
      add :ai_model_version, :string

      # Cache management
      add :cache_valid_until, :utc_datetime
      add :stale, :boolean, default: false

      timestamps()
    end

    create unique_index(:company_research, [:company_name])
    create index(:company_research, [:company_id_external])
    create index(:company_research, [:reputation_score])
    create index(:company_research, [:industry])
    create index(:company_research, [:last_researched_at])
    create index(:company_research, [:cache_valid_until])
  end
end
