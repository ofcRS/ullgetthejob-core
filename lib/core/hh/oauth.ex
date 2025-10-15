defmodule Core.HH.OAuth do
  @moduledoc """
  HH OAuth token storage and refresh helpers.
  """

  import Ecto.Query  # Add this import

  alias Core.Repo
  alias Core.HH.Token

  @type token :: %{
          access_token: binary(),
          refresh_token: binary() | nil,
          expires_at: DateTime.t()
        }

  def upsert_token(user_id, %{} = token) do
    attrs = %{
      user_id: user_id,
      access_token: Map.get(token, :access_token) || Map.get(token, "access_token"),
      refresh_token: Map.get(token, :refresh_token) || Map.get(token, "refresh_token"),
      expires_at: Map.get(token, :expires_at) || Map.get(token, "expires_at")
    }

    %Token{}
    |> Token.changeset(attrs)
    |> Repo.insert()
  end

  def get_latest_token(user_id) do
    Repo.one(from t in Token, where: t.user_id == ^user_id, order_by: [desc: t.inserted_at], limit: 1)
  end
end
