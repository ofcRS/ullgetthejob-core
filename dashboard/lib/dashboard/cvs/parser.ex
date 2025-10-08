defmodule Dashboard.CVs.Parser do
  @moduledoc """
  Parses CV files and extracts structured data using AI.
  """
  require Logger

  alias Dashboard.AI.OpenRouterClient

  @doc """
  Parses a CV file and extracts structured information.

  Returns {:ok, parsed_data} or {:error, reason}
  """
  def parse_file(file_path) do
    case extract_text_from_file(file_path) do
      {:ok, text} ->
        parse_text(text)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parses CV text using OpenRouter AI to extract structured data.
  """
  def parse_text(text) when is_binary(text) do
    case OpenRouterClient.parse_cv_text(text) do
      {:ok, parsed_data} ->
        {:ok, parsed_data}

      {:error, reason} ->
        Logger.error("Failed to parse CV with AI: #{inspect(reason)}")
        # Return a basic structure if AI parsing fails
        {:ok, %{
          personal_info: %{},
          experience: [],
          skills: [],
          projects: [],
          achievements: [],
          raw_text: String.slice(text, 0..500)
        }}
    end
  end

  defp extract_text_from_file(file_path) do
    content_type = MIME.from_path(file_path)

    case content_type do
      "application/pdf" ->
        extract_from_pdf(file_path)

      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ->
        extract_from_docx(file_path)

      "text/plain" ->
        File.read(file_path)

      _ ->
        {:error, :unsupported_format}
    end
  end

  defp extract_from_pdf(file_path) do
    # For now, just read as binary and let AI handle it
    # In a production app, you'd use a PDF parsing library
    case System.cmd("pdftotext", [file_path, "-"], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}

      {error, _} ->
        Logger.warning("pdftotext failed: #{error}")
        # Fallback: return a message indicating PDF needs manual handling
        {:ok, "[PDF file - automated text extraction unavailable. Please install pdftotext or manually copy content.]"}
    end
  rescue
    e ->
      Logger.warning("PDF extraction failed: #{inspect(e)}")
      {:ok, "[PDF file - automated text extraction unavailable]"}
  end

  defp extract_from_docx(_file_path) do
    # For now, return a placeholder
    # In production, use a library like `docx` or `unzip` + XML parsing
    {:ok, "[DOCX file - automated text extraction not yet implemented. Please convert to PDF or TXT.]"}
  end
end
