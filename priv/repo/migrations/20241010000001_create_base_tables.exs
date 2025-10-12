defmodule Core.Repo.Migrations.CreateBaseTables do
  use Ecto.Migration

  def change do
    # Users table
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :email, :string, null: false
      add :password_hash, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    # Jobs table
    create table(:jobs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :external_id, :string, null: false
      add :title, :string, null: false
      add :company, :string
      add :salary, :string
      add :area, :string
      add :url, :text
      add :description, :text
      add :source, :string, default: "hh.ru"
      add :search_query, :string
      add :fetched_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:jobs, [:external_id])
    create index(:jobs, [:source])
    create index(:jobs, [:fetched_at])

    # Applications table
    create table(:applications, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :job_id, references(:jobs, type: :uuid, on_delete: :delete_all)
      add :job_external_id, :string, null: false
      add :cover_letter, :text
      add :status, :string, default: "pending"
      add :submitted_at, :utc_datetime
      add :response_data, :map
      add :error_message, :text
      add :hh_resume_id, :string

      timestamps(type: :utc_datetime)
    end

    create index(:applications, [:user_id])
    create index(:applications, [:job_id])
    create index(:applications, [:status])
    create index(:applications, [:submitted_at])
  end
end
