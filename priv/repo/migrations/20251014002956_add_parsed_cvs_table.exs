defmodule Core.Repo.Migrations.AddParsedCvsTable do
  use Ecto.Migration

  def change do
    create table(:parsed_cvs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :nilify_all)

      # Parsed fields
      add :first_name, :string, size: 100
      add :last_name, :string, size: 100
      add :email, :string, size: 255
      add :phone, :string, size: 50
      add :title, :string, size: 255
      add :summary, :text
      add :experience, :text
      add :education, :text
      add :skills, {:array, :string}, default: []
      add :projects, :text
      add :full_text, :text


      # Metadata
      add :original_filename, :string, size: 255
      add :file_path, :text
      add :model_used, :string, size: 100

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: :updated_at)
    end

    create index(:parsed_cvs, [:user_id])
  end
end
