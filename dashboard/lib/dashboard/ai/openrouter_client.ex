defmodule Dashboard.AI.OpenRouterClient do
  @moduledoc """
  Client for OpenRouter API to interact with various LLM models.

  Supports GPT-4, Claude, and other models via OpenRouter.
  """
  require Logger

  @base_url "https://openrouter.ai/api/v1"

  defp config do
    Application.get_env(:dashboard, __MODULE__, [])
  end

  defp api_key do
    Keyword.get(config(), :api_key) || System.get_env("OPENROUTER_API_KEY")
  end

  defp model do
    Keyword.get(config(), :model, "openai/gpt-4-turbo")
  end

  @doc """
  Parses CV text and extracts structured information.

  Returns {:ok, parsed_data} or {:error, reason}
  """
  def parse_cv_text(text) do
    prompt = """
    Parse the following CV/resume and extract structured information.

    Return a JSON object with the following structure:
    {
      "personal_info": {
        "name": "Full Name",
        "email": "email@example.com",
        "phone": "+1234567890",
        "location": "City, Country",
        "title": "Professional Title"
      },
      "experience": [
        {
          "title": "Job Title",
          "company": "Company Name",
          "period": "Start - End",
          "description": "Key responsibilities and achievements"
        }
      ],
      "skills": ["Skill1", "Skill2", "Skill3"],
      "projects": [
        {
          "name": "Project Name",
          "description": "Brief description",
          "technologies": ["Tech1", "Tech2"]
        }
      ],
      "achievements": ["Achievement 1", "Achievement 2"],
      "education": [
        {
          "degree": "Degree Name",
          "institution": "University Name",
          "year": "Graduation Year"
        }
      ]
    }

    CV Text:
    #{text}
    """

    case chat_completion(prompt) do
      {:ok, response} ->
        parse_json_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Analyzes job requirements from a job description.
  """
  def analyze_job_requirements(job_description) do
    prompt = """
    Analyze the following job description and extract key requirements.

    Return a JSON object with:
    {
      "required_skills": ["Skill1", "Skill2"],
      "preferred_skills": ["Skill3", "Skill4"],
      "experience_level": "Junior/Mid/Senior",
      "key_responsibilities": ["Responsibility1", "Responsibility2"],
      "must_have_keywords": ["Keyword1", "Keyword2"]
    }

    Job Description:
    #{job_description}
    """

    case chat_completion(prompt) do
      {:ok, response} ->
        parse_json_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Suggests CV highlights based on job requirements.
  """
  def suggest_cv_highlights(cv_data, job_requirements) do
    prompt = """
    Given the following CV data and job requirements, suggest which parts of the CV
    should be highlighted or emphasized for this specific job.

    Return a JSON object with:
    {
      "recommended_experiences": [
        {
          "experience_index": 0,
          "relevance_score": 0.95,
          "reason": "Why this experience is relevant"
        }
      ],
      "recommended_skills": ["Skill1", "Skill2"],
      "recommended_projects": [0, 1],
      "suggested_order": {
        "skills": ["Most relevant first"],
        "experiences": [0, 2, 1]
      }
    }

    CV Data:
    #{Jason.encode!(cv_data)}

    Job Requirements:
    #{Jason.encode!(job_requirements)}
    """

    case chat_completion(prompt) do
      {:ok, response} ->
        parse_json_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a cover letter based on CV and job description.
  """
  def generate_cover_letter(cv_data, job_description) do
    personal_info = Map.get(cv_data, "personal_info", %{})
    name = Map.get(personal_info, "name", "")

    prompt = """
    Write a professional cover letter for this job application.

    Guidelines:
    - Keep it concise (3-4 paragraphs)
    - Highlight relevant experience and skills
    - Show enthusiasm for the role
    - Professional but personable tone
    - Do not include address or date (just the letter body)

    Candidate Information:
    #{Jason.encode!(cv_data)}

    Job Description:
    #{job_description}

    Write the cover letter starting with "Dear Hiring Manager," and ending with "Sincerely,\n#{name}"
    """

    case chat_completion(prompt) do
      {:ok, response} ->
        {:ok, String.trim(response)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private Functions

  defp chat_completion(prompt) do
    key = api_key()

    if is_nil(key) or key == "" do
      Logger.error("OpenRouter API key not configured")
      {:error, :api_key_not_configured}
    else
      make_request(prompt, key)
    end
  end

  defp make_request(prompt, key) do
    url = "#{@base_url}/chat/completions"

    headers = [
      {"Authorization", "Bearer #{key}"},
      {"Content-Type", "application/json"},
      {"HTTP-Referer", "https://github.com/yourusername/job-automation"},
      {"X-Title", "HH.ru Job Automation"}
    ]

    body = %{
      model: model(),
      messages: [
        %{
          role: "user",
          content: prompt
        }
      ],
      temperature: 0.7
    }

    Logger.debug("Making OpenRouter API request to #{model()}")

    case Req.post(url, json: body, headers: headers, retry: false) do
      {:ok, %{status: 200, body: response_body}} ->
        extract_content(response_body)

      {:ok, %{status: 401}} ->
        Logger.error("OpenRouter API authentication failed")
        {:error, :unauthorized}

      {:ok, %{status: 429}} ->
        Logger.warning("OpenRouter API rate limited")
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.error("OpenRouter API error #{status}: #{inspect(body)}")
        {:error, {:api_error, status}}

      {:error, reason} ->
        Logger.error("OpenRouter API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_content(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    {:ok, content}
  end

  defp extract_content(response) do
    Logger.error("Unexpected OpenRouter response format: #{inspect(response)}")
    {:error, :unexpected_response_format}
  end

  defp parse_json_response(text) do
    # Try to extract JSON from markdown code blocks if present
    json_text =
      case Regex.run(~r/```json\s*(.*?)\s*```/s, text) do
        [_, json] -> json
        nil -> text
      end

    case Jason.decode(json_text) do
      {:ok, data} ->
        {:ok, data}

      {:error, _} ->
        Logger.warning("Failed to parse JSON response, returning raw text")
        {:ok, %{"raw_response" => text}}
    end
  end
end
