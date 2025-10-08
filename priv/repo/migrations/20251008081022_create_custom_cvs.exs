defmodule Dashboard.Repo.Migrations.CreateCustomCvs do
  use Ecto.Migration

  def change do
    create table(:custom_cvs) do
      add :cv_id, references(:cvs, on_delete: :delete_all), null: false
      add :job_id, references(:jobs, on_delete: :nilify_all)
      add :job_title, :string
      add :customized_data, :map
      add :cover_letter, :text
      add :ai_suggestions, :map

      timestamps(type: :utc_datetime)
    end

    create index(:custom_cvs, [:cv_id])
    create index(:custom_cvs, [:job_id])
  end
end
