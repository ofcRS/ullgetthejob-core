defmodule OrchestratorWeb.HealthController do
  use OrchestratorWeb, :controller

  def health(conn, _params) do
    db_status = case Ecto.Adapters.SQL.query(Orchestrator.Repo, "SELECT 1", []) do
      {:ok, _} -> :up
      _ -> :down
    end

    json(conn, %{status: "ok", db: db_status})
  end
end
