defmodule DashboardWeb.JobsController do
  use DashboardWeb, :controller

  def index(conn, _params) do
    render(conn, :jobs)
  end
end
