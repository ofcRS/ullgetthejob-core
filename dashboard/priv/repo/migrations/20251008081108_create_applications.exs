defmodule Dashboard.Repo.Migrations.CreateApplications do
  use Ecto.Migration

  def change do
    create table(:applications) do
      add :job_id, references(:jobs, on_delete: :nilify_all)
      add :custom_cv_id, references(:custom_cvs, on_delete: :nilify_all)
      add :job_external_id, :string, null: false
      add :cover_letter, :text
      add :status, :string, default: "pending"
      add :submitted_at, :utc_datetime
      add :response_data, :map
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:applications, [:job_external_id])
    create index(:applications, [:status])
    create index(:applications, [:submitted_at])
  end
end
