defmodule Dashboard.CVs.CustomCV do
  @moduledoc """
  Schema for storing job-specific customized CV versions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Dashboard.CVs.CV
  alias Dashboard.Jobs.Job

  schema "custom_cvs" do
    belongs_to :cv, CV
    belongs_to :job, Job
    field :job_title, :string
    field :customized_data, :map
    field :cover_letter, :string
    field :ai_suggestions, :map

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(custom_cv, attrs) do
    custom_cv
    |> cast(attrs, [
      :cv_id,
      :job_id,
      :job_title,
      :customized_data,
      :cover_letter,
      :ai_suggestions
    ])
    |> validate_required([:cv_id])
    |> foreign_key_constraint(:cv_id)
    |> foreign_key_constraint(:job_id)
  end
end
