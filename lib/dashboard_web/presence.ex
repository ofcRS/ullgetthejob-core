defmodule DashboardWeb.Presence do
  @moduledoc """
  Provides presence tracking for LiveView connections.

  This allows us to track how many users are currently viewing the job stream.
  """
  use Phoenix.Presence,
    otp_app: :dashboard,
    pubsub_server: Dashboard.PubSub
end
