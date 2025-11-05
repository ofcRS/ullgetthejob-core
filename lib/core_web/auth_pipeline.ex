defmodule CoreWeb.AuthPipeline do
  @moduledoc """
  Guardian pipeline for authenticating API requests.
  Verifies JWT tokens from the Authorization header.
  """
  use Guardian.Plug.Pipeline,
    otp_app: :core,
    module: Core.Auth.Guardian,
    error_handler: CoreWeb.AuthErrorHandler

  plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource
end
