defmodule Dashboard.Repo.Migrations.CreateCvs do
  use Ecto.Migration

  def change do
    create table(:cvs) do
      add :name, :string, null: false
      add :file_path, :string, null: false
      add :original_filename, :string
      add :content_type, :string
      add :parsed_data, :map
      add :is_active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:cvs, [:is_active])
    create index(:cvs, [:inserted_at])
  end
end
