defmodule Core.Auth.Guardian do
  @moduledoc """
  Guardian implementation for JWT-based authentication.
  Handles token generation and validation for API authentication.
  """
  use Guardian, otp_app: :core

  alias Core.Repo
  alias Core.HH.Token

  @doc """
  Encode the user/session into the token subject.
  For HH.ru OAuth, we use the user_id as the subject.
  """
  def subject_for_token(%{id: id}, _claims) when is_binary(id) do
    {:ok, to_string(id)}
  end

  def subject_for_token(%Token{user_id: user_id}, _claims) when is_binary(user_id) do
    {:ok, to_string(user_id)}
  end

  def subject_for_token(_, _), do: {:error, :no_id}

  @doc """
  Retrieve the user/resource from the token claims.
  Returns a minimal resource map with the user_id.
  """
  def resource_from_claims(%{"sub" => id}) do
    {:ok, %{id: id}}
  end

  def resource_from_claims(_), do: {:error, :invalid_claims}

  @doc """
  Generate a JWT token for a user_id.
  """
  def generate_token(user_id) when is_binary(user_id) do
    create_token(%{id: user_id}, %{})
  end

  @doc """
  Verify and decode a JWT token.
  """
  def verify_token(token) when is_binary(token) do
    decode_and_verify(token)
  end
end
