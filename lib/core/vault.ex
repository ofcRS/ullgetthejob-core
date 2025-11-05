defmodule Core.Vault do
  @moduledoc """
  Encryption vault for storing sensitive data using Cloak.
  Uses AES-256-GCM encryption for OAuth tokens and other secrets.
  """
  use Cloak.Vault, otp_app: :core
end
