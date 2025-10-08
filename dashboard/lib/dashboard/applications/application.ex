defmodule Dashboard.Applications.Application do
  @moduledoc """
  Schema for tracking job applications.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Dashboard.Jobs.Job
  alias Dashboard.CVs.CustomCV

  schema "applications" do
    belongs_to :job, Job
    belongs_to :custom_cv, CustomCV
    field :job_external_id, :string
    field :cover_letter, :string
    field :status, :string, default: "pending"
    field :submitted_at, :utc_datetime
    field :response_data, :map
    field :error_message, :string
    field :hh_resume_id, :string
    field :hh_negotiation_id, :string

    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(pending submitted failed error)

  @doc false
  def changeset(application, attrs) do
    application
    |> cast(attrs, [
      :job_id,
      :custom_cv_id,
      :job_external_id,
      :cover_letter,
      :status,
      :submitted_at,
      :response_data,
      :error_message,
      :hh_resume_id,
      :hh_negotiation_id
    ])
    |> validate_required([:job_external_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:job_id)
    |> foreign_key_constraint(:custom_cv_id)
  end
end
