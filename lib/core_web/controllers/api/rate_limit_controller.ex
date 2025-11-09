defmodule CoreWeb.Api.RateLimitController do
  use CoreWeb, :controller
  require Logger

  alias Core.RateLimiter

  plug :verify_orchestrator_secret

  @doc """
  Get rate limit status for user
  """
  def status(conn, %{"user_id" => user_id}) do
    rate_status = RateLimiter.get_status(user_id)

    # Calculate next refill time
    now = System.system_time(:second)
    last_refill = rate_status.last_refill || now
    seconds_until_refill = 3600 - rem(now - last_refill, 3600)
    next_refill = DateTime.from_unix!(now + seconds_until_refill)

    # TODO: Count applications today from applications table
    applications_today = 0

    json(conn, %{
      success: true,
      tokens: rate_status.tokens,
      capacity: rate_status.capacity,
      refill_rate: rate_status.refill_rate,
      next_refill: next_refill,
      can_apply: rate_status.tokens > 0,
      applications_today: applications_today
    })
  end

  defp verify_orchestrator_secret(conn, _opts) do
    secret = conn |> get_req_header("x-core-secret") |> List.first()
    expected = System.get_env("ORCHESTRATOR_SECRET")

    if secret == expected do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Unauthorized"})
      |> halt()
    end
  end
end
