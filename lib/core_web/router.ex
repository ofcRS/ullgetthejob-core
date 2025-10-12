defmodule CoreWeb.Router do
  use CoreWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Internal API for other services
  scope "/api/v1", CoreWeb do
    pipe_through :api

    get "/system/health", SystemController, :health
    post "/rate-limit/check", RateLimitController, :check
    post "/jobs/broadcast-dummy", SystemController, :broadcast_dummy
  end

  # API for Node.js BFF
  scope "/api", CoreWeb.Api do
    pipe_through :api

    post "/jobs/search", JobController, :search
    post "/applications/submit", ApplicationController, :submit
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:core, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: CoreWeb.Telemetry
    end
  end
end
