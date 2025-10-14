defmodule Core.HH.Token do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "hh_tokens" do
    field :user_id, :binary_id
    field :access_token, :string
    field :refresh_token, :string
    field :expires_at, :utc_datetime
    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:user_id, :access_token, :refresh_token, :expires_at])
    |> validate_required([:access_token, :expires_at])
  end
end
