defmodule CoreWeb.HHController do
  use CoreWeb, :controller
  alias Core.HH.{OAuth, Client}

  def resumes(conn, _params) do
    # MVP: pick latest stored token without user
    case OAuth.get_latest_token(nil) do
      nil -> conn |> put_status(404) |> json(%{success: false, error: "No tokens"})
      token ->
        case Client.fetch_user_resumes(token.access_token) do
          {:ok, items} -> json(conn, %{success: true, items: items})
          {:error, reason} -> conn |> put_status(502) |> json(%{success: false, error: inspect(reason)})
        end
    end
  end

  def resume_details(conn, %{"id" => id}) do
    case OAuth.get_latest_token(nil) do
      nil -> conn |> put_status(404) |> json(%{success: false, error: "No tokens"})
      token ->
        case Client.fetch_resume_details(id, token.access_token) do
          {:ok, resume} -> json(conn, %{success: true, resume: resume})
          {:error, reason} -> conn |> put_status(502) |> json(%{success: false, error: inspect(reason)})
        end
    end
  end
end
