defmodule Dashboard.Repo.Migrations.CreateJobs do
  use Ecto.Migration

  def change do
    create table(:jobs) do
      add :external_id, :string, null: false
      add :title, :string, null: false
      add :company, :string
      add :salary, :string
      add :area, :string
      add :url, :text
      add :source, :string, default: "hh.ru"
      add :search_query, :string
      add :fetched_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:jobs, [:external_id])
    create index(:jobs, [:title])
    create index(:jobs, [:company])
    create index(:jobs, [:area])
    create index(:jobs, [:fetched_at])
  end
end
