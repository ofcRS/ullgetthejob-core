defmodule CoreWeb.AuthErrorHandler do
  @moduledoc """
  Handles authentication errors from Guardian pipeline.
  Returns standardized JSON error responses.
  """
  import Plug.Conn
  require Logger

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, _reason}, _opts) do
    Logger.warning("Authentication error: #{type}")

    body =
      Jason.encode!(%{
        error: %{
          code: "AUTH_FAILED",
          message: error_message(type),
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
  end

  defp error_message(:invalid_token), do: "Invalid authentication token"
  defp error_message(:token_expired), do: "Authentication token has expired"
  defp error_message(:no_token), do: "No authentication token provided"
  defp error_message(:unauthenticated), do: "Authentication required"
  defp error_message(_), do: "Authentication failed"
end
