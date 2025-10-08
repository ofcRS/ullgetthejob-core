defmodule Dashboard.Applications.Applicator do
  @moduledoc """
  Module responsible for submitting job applications to HH.ru.
  """
  require Logger

  alias Dashboard.HH.Client, as: HHClient
  alias Dashboard.Applications
  alias Dashboard.Applications.Application

  @doc """
  Submits an application to HH.ru.

  ## Parameters
    - application: The Application struct to submit

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def submit_application(%Application{} = application) do
    Logger.info("Submitting application for job #{application.job_external_id}")

    # Check daily limit
    case check_daily_limit() do
      :ok ->
        do_submit(application)

      {:error, reason} ->
        Applications.update_application(application, %{
          status: "failed",
          error_message: "Daily limit exceeded"
        })
        {:error, reason}
    end
  end

  # Private Functions

  defp do_submit(application) do
    # For now, this is a stub implementation
    # In a real implementation, this would:
    # 1. Get the job application page from HH.ru
    # 2. Parse the form and CSRF token
    # 3. Upload CV if needed
    # 4. Submit the application form
    # 5. Parse the response

    Logger.info("Getting job application page...")

    case get_application_page(application.job_external_id) do
      {:ok, _page_html} ->
        # For now, just simulate a successful submission
        Logger.info("Simulating application submission (not actually submitting)")

        # Update application status
        Applications.update_application(application, %{
          status: "submitted",
          submitted_at: DateTime.utc_now(),
          response_data: %{
            "simulation" => true,
            "message" => "This is a simulated submission. Real implementation coming soon."
          }
        })

        {:ok, %{success: true, message: "Application submitted (simulated)"}}

      {:error, reason} ->
        Logger.error("Failed to get application page: #{inspect(reason)}")

        Applications.update_application(application, %{
          status: "failed",
          error_message: "Failed to access HH.ru: #{inspect(reason)}"
        })

        {:error, reason}
    end
  end

  defp get_application_page(job_external_id) do
    # Construct the job URL
    job_url = "/vacancy/#{job_external_id}"

    case HHClient.get(job_url, base_url: "https://hh.ru") do
      {:ok, html} ->
        {:ok, html}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_daily_limit do
    config = Elixir.Application.get_env(:dashboard, Dashboard.Applications, [])
    max_daily = Keyword.get(config, :max_daily_applications, 10)

    today_count = Applications.count_applications_today()

    if today_count >= max_daily do
      Logger.warning("Daily application limit reached: #{today_count}/#{max_daily}")
      {:error, :daily_limit_exceeded}
    else
      Logger.info("Daily application count: #{today_count}/#{max_daily}")
      :ok
    end
  end
end
