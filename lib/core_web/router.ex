defmodule CoreWeb.Router do
  use CoreWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Protected API pipeline with JWT authentication
  pipeline :api_protected do
    plug :accepts, ["json"]
    plug CoreWeb.AuthPipeline
  end

  # Internal API for other services
  scope "/api/v1", CoreWeb do
    pipe_through :api

    get "/system/health", SystemController, :health
    post "/rate-limit/check", RateLimitController, :check
    post "/jobs/broadcast-dummy", SystemController, :broadcast_dummy
  end

  # API for Node.js BFF (protected with internal secret)
  scope "/api", CoreWeb.Api do
    pipe_through :api

    post "/jobs/search", JobController, :search
    get "/jobs/:id", JobController, :show
    post "/applications/submit", ApplicationController, :submit
  end

  # OAuth endpoints (public)
  scope "/auth/hh", CoreWeb do
    pipe_through :api
    get "/redirect", AuthController, :redirect
    get "/callback", AuthController, :callback
    post "/refresh", AuthController, :refresh
  end

  # HH.ru API endpoints (can be protected if needed)
  # For now, keeping them unprotected as they're used by the orchestrator
  scope "/api/hh", CoreWeb do
    pipe_through :api
    get "/status", HHController, :status
    get "/resumes", HHController, :resumes
    get "/resumes/:id", HHController, :resume_details
  end

  # Example of protected routes (uncomment when needed)
  # scope "/api/protected", CoreWeb do
  #   pipe_through :api_protected
  #
  #   get "/user/profile", UserController, :profile
  #   put "/user/settings", UserController, :update_settings
  # end

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
