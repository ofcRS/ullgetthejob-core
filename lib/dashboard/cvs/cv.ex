defmodule Dashboard.CVs.CV do
  @moduledoc """
  Schema for storing CV/resume files and their parsed data.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "cvs" do
    field :name, :string
    field :file_path, :string
    field :original_filename, :string
    field :content_type, :string
    field :parsed_data, :map
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(cv, attrs) do
    cv
    |> cast(attrs, [
      :name,
      :file_path,
      :original_filename,
      :content_type,
      :parsed_data,
      :is_active
    ])
    |> validate_required([:name, :file_path])
    |> validate_content_type()
  end

  defp validate_content_type(changeset) do
    case get_field(changeset, :content_type) do
      nil ->
        changeset

      content_type ->
        if content_type in [
             "application/pdf",
             "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
             "text/plain"
           ] do
          changeset
        else
          add_error(changeset, :content_type, "must be PDF, DOCX, or TXT")
        end
    end
  end
end
