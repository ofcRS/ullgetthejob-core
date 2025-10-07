defmodule DashboardWeb.JobsController do
  use DashboardWeb, :controller

  def index(conn, _params) do
    IO.puts("OMFG! My first ouput to console!!!!!!!!!")
    render(conn, :jobs)
  end
end
