defmodule CoreWeb.HHController do
  use CoreWeb, :controller
  alias Core.HH.{OAuth, Client}

  def status(conn, _params) do
    with {:ok, access_token} <- fetch_access_token(conn),
         {:ok, _items} <- Client.fetch_user_resumes(access_token) do
      json(conn, %{connected: true})
    else
      {:error, :no_valid_token} ->
        conn |> put_status(:unauthorized) |> json(%{connected: false, error: "No valid HH token"})

      {:error, {:http_error, status}} ->
        conn |> put_status(status) |> json(%{connected: false, error: "HH API error"})

      {:error, reason} ->
        conn |> put_status(502) |> json(%{connected: false, error: inspect(reason)})
    end
  end

  def resumes(conn, _params) do
    with {:ok, access_token} <- fetch_access_token(conn),
         {:ok, items} <- Client.fetch_user_resumes(access_token) do
      json(conn, %{success: true, items: items})
    else
      {:error, :no_valid_token} ->
        conn |> put_status(:unauthorized) |> json(%{success: false, error: "No valid HH token"})

      {:error, {:http_error, status}} ->
        conn |> put_status(status) |> json(%{success: false, error: "HH API error"})

      {:error, reason} ->
        conn |> put_status(502) |> json(%{success: false, error: inspect(reason)})
    end
  end

  def resume_details(conn, %{"id" => id}) do
    with {:ok, access_token} <- fetch_access_token(conn),
         {:ok, resume} <- Client.fetch_resume_details(id, access_token) do
      json(conn, %{success: true, resume: resume})
    else
      {:error, :no_valid_token} ->
        conn |> put_status(:unauthorized) |> json(%{success: false, error: "No valid HH token"})

      {:error, {:http_error, status}} ->
        conn |> put_status(status) |> json(%{success: false, error: "HH API error"})

      {:error, reason} ->
        conn |> put_status(502) |> json(%{success: false, error: inspect(reason)})
    end
  end

  defp fetch_access_token(conn) do
    header_token =
      conn
      |> get_req_header("authorization")
      |> List.first()
      |> parse_bearer()

    case header_token do
      {:ok, token} -> {:ok, token}
      _ ->
        conn
        |> get_req_header("x-session-id")
        |> List.first()
        |> OAuth.get_valid_token()
    end
  end

  defp parse_bearer("Bearer " <> token) when byte_size(token) > 0, do: {:ok, token}
  defp parse_bearer(_), do: :error
end
