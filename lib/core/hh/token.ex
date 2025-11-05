defmodule Core.HH.Token do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "hh_tokens" do
    field :user_id, :binary_id
    # Encrypted fields - stored as binary in DB, automatically encrypted/decrypted
    field :access_token, Core.Encrypted.Binary
    field :refresh_token, Core.Encrypted.Binary
    field :expires_at, :utc_datetime
    timestamps()
  end

  @doc """
  Changeset for creating or updating HH.ru OAuth tokens.
  Tokens are automatically encrypted before storage.
  """
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:user_id, :access_token, :refresh_token, :expires_at])
    |> validate_required([:access_token, :expires_at])
    |> unique_constraint(:user_id)
  end
end
