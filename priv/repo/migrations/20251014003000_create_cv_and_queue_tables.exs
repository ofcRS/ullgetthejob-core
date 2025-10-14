defmodule Core.Repo.Migrations.CreateCvAndQueueTables do
  use Ecto.Migration

  def change do
    # CVs table
    create table(:cvs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :file_path, :text, null: false
      add :original_filename, :string
      add :content_type, :string
      add :parsed_data, :map
      add :is_active, :boolean, default: true

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: :updated_at)
    end

    create index(:cvs, [:user_id])

    # Custom CVs table
    create table(:custom_cvs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :cv_id, references(:cvs, type: :uuid, on_delete: :delete_all), null: false
      add :job_id, references(:jobs, type: :uuid, on_delete: :nilify_all)
      add :job_title, :string
      add :customized_data, :map
      add :cover_letter, :text
      add :ai_suggestions, :map

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: :updated_at)
    end

    create index(:custom_cvs, [:cv_id])
    create index(:custom_cvs, [:job_id])

    # Application queue table
    create table(:application_queue, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :workflow_id, :uuid, null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :cv_id, references(:cvs, type: :uuid, on_delete: :delete_all), null: false
      add :job_id, references(:jobs, type: :uuid, on_delete: :nilify_all)
      add :job_external_id, :string, null: false
      add :status, :string, default: "pending"
      add :payload, :map
      add :attempts, :integer, default: 0
      add :next_run_at, :utc_datetime, default: fragment("now()")
      add :priority, :integer, default: 0
      add :last_error, :text

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: :updated_at)
    end

    create index(:application_queue, [:user_id])
    create index(:application_queue, [:cv_id])
    create index(:application_queue, [:job_id])
    create index(:application_queue, [:status])
    create index(:application_queue, [:next_run_at])
    create index(:application_queue, [:priority])
  end
end
