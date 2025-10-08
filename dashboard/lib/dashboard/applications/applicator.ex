defmodule Dashboard.Applications.Applicator do
  @moduledoc """
  Submits job applications to HH.ru using OAuth API.
  """
  require Logger
  import Ecto.Query

  alias Dashboard.HH.Client
  alias Dashboard.HH.ResumeManager
  alias Dashboard.Applications
  alias Dashboard.Applications.Application
  alias Dashboard.CVEditor
  alias Dashboard.Repo

  @doc """
  Submits an application to HH.ru.

  Process:
  1. Check daily limit
  2. Get or create resume on HH.ru
  3. Ensure resume is published
  4. Submit application (create negotiation)
  5. Add cover letter if provided
  6. Update application record
  """
  def submit_application(%Application{} = application) do
    Logger.info("Submitting application for job #{application.job_external_id}")

    with :ok <- check_daily_limit(),
         {:ok, custom_cv} <- get_custom_cv(application),
         {:ok, resume_id} <- ensure_hh_resume(custom_cv),
         {:ok, negotiation} <- create_negotiation(application.job_external_id, resume_id),
         :ok <- add_cover_letter(negotiation["id"], application.cover_letter) do

      # Success! Update application
      Applications.update_application(application, %{
        status: "submitted",
        submitted_at: DateTime.utc_now(),
        hh_resume_id: resume_id,
        hh_negotiation_id: negotiation["id"],
        response_data: %{
          "negotiation" => negotiation,
          "submitted_via" => "api"
        }
      })

      {:ok, %{
        success: true,
        negotiation_id: negotiation["id"],
        message: "Application submitted successfully"
      }}
    else
      {:error, :daily_limit_exceeded} = error ->
        update_failed(application, "Daily limit exceeded")
        error

      {:error, reason} = error ->
        Logger.error("Application failed: #{inspect(reason)}")
        update_failed(application, inspect(reason))
        error
    end
  end

  # Private Functions

  defp get_custom_cv(%Application{custom_cv_id: nil}), do: {:error, :no_custom_cv}

  defp get_custom_cv(%Application{custom_cv_id: custom_cv_id}) do
    case CVEditor.get_custom_cv(custom_cv_id) do
      {:ok, custom_cv} ->
        # Preload CV if needed
        custom_cv = Repo.preload(custom_cv, :cv)
        {:ok, custom_cv}

      error -> error
    end
  end

  # Gets existing HH.ru resume or creates a new one.
  defp ensure_hh_resume(custom_cv) do
    # Check if we already uploaded this CV
    case get_cached_resume_id(custom_cv.id) do
      {:ok, resume_id} ->
        Logger.info("Using existing HH.ru resume: #{resume_id}")
        {:ok, resume_id}

      :not_found ->
        create_new_resume(custom_cv)
    end
  end

  defp get_cached_resume_id(custom_cv_id) do
    # Check if any application with this CV has a resume_id
    query = from a in Application,
      where: a.custom_cv_id == ^custom_cv_id,
      where: not is_nil(a.hh_resume_id),
      order_by: [desc: a.inserted_at],
      limit: 1,
      select: a.hh_resume_id

    case Repo.one(query) do
      nil -> :not_found
      resume_id -> {:ok, resume_id}
    end
  end

  defp create_new_resume(custom_cv) do
    Logger.info("Creating new resume on HH.ru")

    # Use customized data if available, otherwise use original
    cv_data = custom_cv.customized_data || custom_cv.cv.parsed_data

    case ResumeManager.create_resume(cv_data, title: custom_cv.job_title) do
      {:ok, %{"id" => resume_id}} ->
        # Publish the resume
        case ResumeManager.publish_resume(resume_id) do
          {:ok, _} ->
            Logger.info("Resume published: #{resume_id}")
            {:ok, resume_id}

          {:error, reason} ->
            Logger.warning("Failed to publish resume: #{inspect(reason)}")
            # Still return the resume_id - we can try to apply anyway
            {:ok, resume_id}
        end

      {:error, reason} ->
        Logger.error("Failed to create resume: #{inspect(reason)}")
        {:error, {:resume_creation_failed, reason}}
    end
  end

  # Creates a negotiation (application) on HH.ru.
  # API: POST /negotiations
  # Docs: https://github.com/hhru/api/blob/master/docs/negotiations.md
  defp create_negotiation(vacancy_id, resume_id) do
    params = %{
      vacancy_id: vacancy_id,
      resume_id: resume_id
    }

    case Client.post("/negotiations", params) do
      {:ok, negotiation} when is_map(negotiation) ->
        {:ok, negotiation}

      {:error, :session_expired} ->
        {:error, :token_expired}

      {:error, reason} ->
        {:error, {:negotiation_failed, reason}}
    end
  end

  # Adds cover letter as a message to the negotiation.
  defp add_cover_letter(_negotiation_id, nil), do: :ok
  defp add_cover_letter(_negotiation_id, ""), do: :ok

  defp add_cover_letter(negotiation_id, cover_letter) do
    message = %{
      message: cover_letter
    }

    case Client.post("/negotiations/#{negotiation_id}/messages", message) do
      {:ok, _response} ->
        Logger.info("Cover letter added to negotiation #{negotiation_id}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to add cover letter: #{inspect(reason)}")
        # Don't fail the whole application if cover letter fails
        :ok
    end
  end

  defp update_failed(application, error_message) do
    Applications.update_application(application, %{
      status: "failed",
      error_message: error_message
    })
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
