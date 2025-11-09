defmodule Core.Schema.ApplicationQueue do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "application_queue" do
    field :workflow_id, :binary_id
    field :user_id, :binary_id
    field :cv_id, :binary_id
    field :job_id, :binary_id
    field :job_external_id, :string
    field :status, :string, default: "pending"
    field :payload, :map
    field :attempts, :integer, default: 0
    field :next_run_at, :utc_datetime
    field :priority, :integer, default: 0
    field :last_error, :string

    timestamps(type: :naive_datetime)
  end

  def changeset(queue_item, attrs) do
    queue_item
    |> cast(attrs, [
      :workflow_id,
      :user_id,
      :cv_id,
      :job_id,
      :job_external_id,
      :status,
      :payload,
      :attempts,
      :next_run_at,
      :priority,
      :last_error
    ])
    |> validate_required([:workflow_id, :user_id, :cv_id, :job_external_id])
    |> validate_inclusion(:status, [
      "pending",
      "customizing",
      "ready",
      "submitting",
      "submitted",
      "failed",
      "rate_limited"
    ])
  end
end
