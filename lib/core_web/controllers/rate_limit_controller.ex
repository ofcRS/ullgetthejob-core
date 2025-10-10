defmodule CoreWeb.RateLimitController do
  use CoreWeb, :controller

  def check(conn, %{"cost" => _cost}) do
    # TODO: implement rate limiting logic
    # For now, always allow
    json(conn, %{allowed: true, remaining: 100})
  end

  def check(conn, _params) do
    json(conn, %{error: "cost parameter required"})
  end
end
