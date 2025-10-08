defmodule Dashboard.Jobs.Job do
  @moduledoc """
  Schema for storing job postings.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "jobs" do
    field :external_id, :string
    field :title, :string
    field :company, :string
    field :salary, :string
    field :area, :string
    field :url, :string
    field :source, :string
    field :search_query, :string
    field :fetched_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :external_id,
      :title,
      :company,
      :salary,
      :area,
      :url,
      :source,
      :search_query,
      :fetched_at
    ])
    |> validate_required([:external_id, :title])
    |> unique_constraint(:external_id)
  end
end
