defmodule Core.HH.OAuth do
  @moduledoc """
  HH OAuth token storage and refresh helpers.
  """

  import Ecto.Query
  require Logger

  alias Core.Repo
  alias Core.HH.Token

  @hh_token_url "https://hh.ru/oauth/token"

  @type token_map :: %{
          optional(:access_token) => binary(),
          optional(:refresh_token) => binary() | nil,
          optional(:expires_at) => DateTime.t() | binary()
        }

  @spec upsert_token(binary() | nil, token_map()) :: {:ok, Token.t()} | {:error, Ecto.Changeset.t()}
  def upsert_token(user_id, %{} = attrs) do
    normalized = normalize_attrs(user_id, attrs)

    Repo.transaction(fn ->
      case get_latest_token(user_id) do
        nil ->
          %Token{}
          |> Token.changeset(normalized)
          |> Repo.insert()

        %Token{} = token ->
          token
          |> Token.changeset(normalized)
          |> Repo.update()
      end
    end)
    |> case do
      {:ok, {:ok, record}} -> {:ok, record}
      {:ok, {:error, changeset}} -> {:error, changeset}
      {:error, reason} ->
        Logger.error("Failed to upsert HH token: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec get_valid_token(binary() | nil) :: {:ok, binary()} | {:error, term()}
  def get_valid_token(user_id) do
    with %Token{} = token <- get_latest_token(user_id) do
      case DateTime.compare(token.expires_at, DateTime.utc_now()) do
        :gt -> {:ok, token.access_token}
        _ -> refresh_token(token)
      end
    else
      nil -> {:error, :no_valid_token}
    end
  end

  @spec get_latest_token(binary() | nil) :: Token.t() | nil
  def get_latest_token(user_id) do
    base_query =
      case user_id do
        nil -> from t in Token, where: is_nil(t.user_id)
        _ -> from t in Token, where: t.user_id == ^user_id
      end

    base_query
    |> order_by([t], desc: t.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp refresh_token(%Token{refresh_token: refresh_token} = token) when is_binary(refresh_token) do
    # Use explicit transaction to ensure atomicity of token refresh
    Repo.transaction(fn ->
      with {:ok, attrs} <- request_refresh(refresh_token),
           normalized <- normalize_attrs(token.user_id, attrs),
           normalized <- Map.update(normalized, :refresh_token, refresh_token, fn
             nil -> refresh_token
             value -> value
           end),
           {:ok, updated} <-
             token
             |> Token.changeset(normalized)
             |> Repo.update()
      do
        updated.access_token
      else
        {:error, :no_refresh_token} = error ->
          Logger.error("Failed to refresh HH token: #{inspect(error)}")
          Repo.rollback(error)

        {:error, {:http_error, _status, _body} = error} ->
          Logger.error("Failed to refresh HH token: #{inspect(error)}")
          Repo.rollback(error)

        {:error, changeset} ->
          Logger.error("Failed to persist refreshed HH token: #{inspect(changeset)}")
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, access_token} -> {:ok, access_token}
      {:error, reason} -> {:error, reason}
    end
  end

  defp refresh_token(%Token{}) do
    {:error, :no_refresh_token}
  end

  defp request_refresh(refresh_token) do
    client_id = System.fetch_env!("HH_CLIENT_ID")
    client_secret = System.fetch_env!("HH_CLIENT_SECRET")

    form = [
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: client_id,
      client_secret: client_secret
    ]

    case Req.post(@hh_token_url, form: form, headers: [{"Content-Type", "application/x-www-form-urlencoded"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, normalize_token_response(body)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("HH token refresh error status=#{status} body=#{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("HH token refresh request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp normalize_attrs(user_id, attrs) do
    expires_at =
      case Map.get(attrs, :expires_at) || Map.get(attrs, "expires_at") do
        %DateTime{} = dt -> dt
        %NaiveDateTime{} = ndt -> DateTime.from_naive!(ndt, "Etc/UTC")
        value when is_binary(value) ->
          case DateTime.from_iso8601(value) do
            {:ok, dt, _offset} -> dt
            _ -> DateTime.utc_now()
          end
        nil -> DateTime.add(DateTime.utc_now(), 3600)
      end

    %{
      user_id: user_id,
      access_token: Map.get(attrs, :access_token) || Map.get(attrs, "access_token"),
      refresh_token: Map.get(attrs, :refresh_token) || Map.get(attrs, "refresh_token"),
      expires_at: expires_at
    }
  end

  defp normalize_token_response(%{"access_token" => at, "refresh_token" => rt, "expires_in" => ttl}) do
    %{
      access_token: at,
      refresh_token: rt,
      expires_at: DateTime.add(DateTime.utc_now(), ttl)
    }
  end

  defp normalize_token_response(%{"access_token" => at, "expires_in" => ttl}) do
    %{
      access_token: at,
      refresh_token: nil,
      expires_at: DateTime.add(DateTime.utc_now(), ttl)
    }
  end

  defp normalize_token_response(other), do: other
end
