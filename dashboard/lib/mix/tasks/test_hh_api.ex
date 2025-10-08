defmodule Mix.Tasks.TestHhApi do
  @moduledoc """
  Tests HH.ru API integration.

  Usage:
    mix test_hh_api
  """
  use Mix.Task
  require Logger
  import Ecto.Query

  @shortdoc "Tests HH.ru API integration"

  def run(_args) do
    Mix.Task.run("app.start")

    Logger.info("Testing HH.ru API...")

    # Test 1: List resumes
    Logger.info("1. Listing resumes...")
    case Dashboard.HH.ResumeManager.list_resumes() do
      {:ok, resumes} ->
        Logger.info("✓ Found #{length(resumes)} resumes")
        Enum.each(resumes, fn r ->
          Logger.info("  - #{r["title"]} (ID: #{r["id"]})")
        end)

      {:error, reason} ->
        Logger.error("✗ Failed to list resumes: #{inspect(reason)}")
    end

    # Test 2: Get a test CV
    Logger.info("2. Getting test CV...")
    cv = get_active_cv()

    if cv do
      Logger.info("✓ Found CV: #{cv.name}")

      # Test 3: Create resume
      Logger.info("3. Creating test resume on HH.ru...")
      case Dashboard.HH.ResumeManager.create_resume(cv.parsed_data, title: "Test Resume - #{DateTime.utc_now()}") do
        {:ok, %{"id" => resume_id}} ->
          Logger.info("✓ Created resume: #{resume_id}")

          # Test 4: Publish resume
          Logger.info("4. Publishing resume...")
          case Dashboard.HH.ResumeManager.publish_resume(resume_id) do
            {:ok, _} ->
              Logger.info("✓ Resume published successfully")

            {:error, reason} ->
              Logger.error("✗ Failed to publish: #{inspect(reason)}")
          end

        {:error, reason} ->
          Logger.error("✗ Failed to create resume: #{inspect(reason)}")
      end
    else
      Logger.error("✗ No CV found. Please upload one first.")
    end

    Logger.info("Test complete!")
  end

  defp get_active_cv do
    Dashboard.Repo.one(
      from cv in Dashboard.CVs.CV,
      where: cv.is_active == true,
      order_by: [desc: cv.inserted_at],
      limit: 1
    )
  end
end
