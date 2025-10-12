defmodule Core.Repo.Migrations.AddHHFields do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :hh_vacancy_id, :string
      add :has_test, :boolean, default: false, null: false
      add :test_required, :boolean, default: false, null: false
      add :employer_id, :string
      add :skills, {:array, :string}, default: []
    end

    create unique_index(:jobs, [:hh_vacancy_id])

    alter table(:applications) do
      add :hh_negotiation_id, :string
      add :hh_status, :string
      add :rate_limited_until, :utc_datetime
    end
  end
end
