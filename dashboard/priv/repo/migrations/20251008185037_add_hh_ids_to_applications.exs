defmodule Dashboard.Repo.Migrations.AddHhIdsToApplications do
  use Ecto.Migration

  def change do
    alter table(:applications) do
      add :hh_resume_id, :string
      add :hh_negotiation_id, :string
    end

    create index(:applications, [:hh_resume_id])
    create index(:applications, [:hh_negotiation_id])
  end
end
