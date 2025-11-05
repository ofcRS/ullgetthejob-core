defmodule CoreWeb.Errors do
  @moduledoc """
  Unified error format and error handling utilities.
  Provides consistent error responses across the application.
  """

  @type error_code :: String.t()
  @type error_message :: String.t()
  @type error_details :: map() | nil

  @doc """
  Create a standardized error response.
  """
  @spec error_response(error_code(), error_message(), error_details()) :: map()
  def error_response(code, message, details \\ nil) do
    error = %{
      code: code,
      message: message,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    if details, do: Map.put(error, :details, details), else: error
  end

  @doc """
  Translate common error reasons to user-friendly messages.
  """
  @spec translate_error(atom() | tuple()) :: {error_code(), error_message()}
  def translate_error(:no_valid_token),
    do: {"AUTH_TOKEN_EXPIRED", "HH.ru authentication token has expired or is invalid"}

  def translate_error(:no_refresh_token),
    do: {"AUTH_NO_REFRESH", "No refresh token available to renew authentication"}

  def translate_error(:missing_resume_id),
    do: {"RESUME_MISSING_ID", "Resume ID is required but not provided"}

  def translate_error(:resume_not_available),
    do: {"RESUME_NOT_AVAILABLE", "Resume is not available for job applications"}

  def translate_error({:http_error, 400, _body}),
    do: {"BAD_REQUEST", "Invalid request parameters"}

  def translate_error({:http_error, 401, _body}),
    do: {"UNAUTHORIZED", "Authentication credentials are invalid"}

  def translate_error({:http_error, 403, _body}),
    do: {"FORBIDDEN", "You do not have permission to perform this action"}

  def translate_error({:http_error, 404, _body}),
    do: {"NOT_FOUND", "The requested resource was not found"}

  def translate_error({:http_error, 429, _body}),
    do: {"RATE_LIMITED", "Too many requests. Please try again later"}

  def translate_error({:http_error, status, _body}) when status >= 500,
    do: {"EXTERNAL_SERVICE_ERROR", "External service is temporarily unavailable"}

  def translate_error({:forbidden, details}),
    do: {"FORBIDDEN", "Action forbidden: #{inspect(details)}"}

  def translate_error({:bad_arguments, _body}),
    do: {"BAD_ARGUMENTS", "Invalid arguments provided"}

  def translate_error(reason),
    do: {"INTERNAL_ERROR", "An unexpected error occurred: #{inspect(reason)}"}

  @doc """
  Create a standardized error response from an error reason.
  """
  @spec from_reason(atom() | tuple(), error_details()) :: map()
  def from_reason(reason, details \\ nil) do
    {code, message} = translate_error(reason)
    error_response(code, message, details)
  end
end
