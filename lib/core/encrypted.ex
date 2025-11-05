defmodule Core.Encrypted do
  @moduledoc """
  Custom encrypted types for sensitive data.
  """

  defmodule Binary do
    @moduledoc """
    Encrypted binary field type that automatically encrypts/decrypts data.
    Used for storing OAuth tokens and other sensitive strings.
    """
    use Cloak.Ecto.Binary, vault: Core.Vault
  end
end
