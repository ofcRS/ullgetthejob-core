defmodule Core.Repo.Migrations.CreateHhTokens do
  use Ecto.Migration

  def change do
    create table(:hh_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :binary_id, null: true
      add :access_token, :text, null: false
      add :refresh_token, :text, null: false
      add :expires_at, :utc_datetime, null: false
      timestamps()
    end

    create index(:hh_tokens, [:user_id])
  end
end
