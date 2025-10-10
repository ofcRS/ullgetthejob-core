defmodule CoreWeb.SystemController do
  use CoreWeb, :controller

  def health(conn, _params) do
    db_status = case Ecto.Adapters.SQL.query(Core.Repo, "SELECT 1", []) do
      {:ok, _} -> :up
      _ -> :down
    end

    json(conn, %{status: "ok", db: db_status})
  end

  def broadcast_dummy(conn, _params) do
    case Core.Broadcaster.broadcast_dummy_jobs() do
      {:ok, count} ->
        json(conn, %{ok: true, broadcasted: count})
      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "Failed to broadcast", reason: inspect(reason)})
    end
  end
end
