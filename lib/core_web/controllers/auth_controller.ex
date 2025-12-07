defmodule CoreWeb.AuthController do
  use CoreWeb, :controller
  require Logger

  @hh_auth_url "https://hh.ru/oauth/authorize"
  @hh_token_url "https://hh.ru/oauth/token"

  def redirect(conn, _params) do
    client_id = System.fetch_env!("HH_CLIENT_ID")
    redirect_uri = System.fetch_env!("HH_REDIRECT_URI")
    state = Ecto.UUID.generate()
    Logger.info("OAuth redirect - client_id=#{client_id} redirect_uri=#{redirect_uri}")
    url = URI.new!(@hh_auth_url)
    |> URI.append_query("response_type=code")
    |> URI.append_query("client_id=#{client_id}")
    |> URI.append_query("redirect_uri=#{URI.encode_www_form(redirect_uri)}")
    |> URI.to_string()
    Logger.info("Generated OAuth URL: #{url}")
    json(conn, %{url: url, state: state})
  end

  def callback(conn, params) do
    session_id = Map.get(params, "session_id")

    with {:ok, code} <- fetch_code(params),
         {:ok, tokens} <- exchange_code_for_tokens(code),
         {:ok, _record} <- Core.HH.OAuth.upsert_token(session_id, tokens),
         {:ok, jwt, _claims} <- Core.Auth.Guardian.generate_token(session_id) do
      Logger.info("OAuth callback successful - generated JWT for session #{session_id}")
      json(conn, %{success: true, jwt: jwt, session_id: session_id})
    else
      {:error, changeset = %Ecto.Changeset{}} ->
        Logger.error("Failed to store HH tokens: #{inspect(changeset)}")
        conn |> put_status(500) |> json(%{success: false, error: "Failed to persist tokens"})

      {:error, reason} ->
        Logger.error("OAuth callback failed: #{inspect(reason)}")
        conn |> put_status(400) |> json(%{success: false, error: inspect(reason)})
    end
  end

  def refresh(conn, params) do
    with {:ok, refresh_token} <- fetch_refresh_token(params),
         {:ok, tokens} <- refresh_tokens(refresh_token) do
      json(conn, %{success: true, tokens: tokens})
    else
      {:error, reason} ->
        conn |> put_status(400) |> json(%{success: false, error: inspect(reason)})
    end
  end

  defp fetch_code(%{"code" => code}) when is_binary(code), do: {:ok, code}
  defp fetch_code(_), do: {:error, :missing_code}

  defp fetch_refresh_token(%{"refresh_token" => rt}) when is_binary(rt), do: {:ok, rt}
  defp fetch_refresh_token(_), do: {:error, :missing_refresh_token}

  defp exchange_code_for_tokens(code) do
    client_id = System.fetch_env!("HH_CLIENT_ID")
    client_secret = System.fetch_env!("HH_CLIENT_SECRET")
    redirect_uri = System.fetch_env!("HH_REDIRECT_URI")
    Logger.info("OAuth token exchange - code_received? #{is_binary(code)} redirect_uri=#{redirect_uri}")

    form = [
      grant_type: "authorization_code",
      code: code,
      client_id: client_id,
      client_secret: client_secret,
      redirect_uri: redirect_uri
    ]

    case Req.post(@hh_token_url, form: form, headers: [{"Content-Type", "application/x-www-form-urlencoded"}]) do
      {:ok, %{status: 200, body: body}} -> {:ok, normalize_tokens(body)}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp refresh_tokens(refresh_token) do
    client_id = System.fetch_env!("HH_CLIENT_ID")
    client_secret = System.fetch_env!("HH_CLIENT_SECRET")

    form = [
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: client_id,
      client_secret: client_secret
    ]

    case Req.post(@hh_token_url, form: form, headers: [{"Content-Type", "application/x-www-form-urlencoded"}]) do
      {:ok, %{status: 200, body: body}} -> {:ok, normalize_tokens(body)}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_tokens(%{"access_token" => at, "refresh_token" => rt, "expires_in" => ttl}) do
    %{
      access_token: at,
      refresh_token: rt,
      expires_at: DateTime.add(DateTime.utc_now(), ttl)
    }
  end
  defp normalize_tokens(%{"access_token" => at, "expires_in" => ttl}) do
    %{
      access_token: at,
      expires_at: DateTime.add(DateTime.utc_now(), ttl)
    }
  end
  defp normalize_tokens(other), do: other
end
