defmodule Core.AI.Matching.FeatureExtractor do
  @moduledoc """
  Feature extraction from jobs and user profiles for AI matching.

  Extracts and normalizes features from:
  - Job descriptions and requirements
  - User CVs and profiles
  - Company data
  - Historical application data

  Features are structured for efficient similarity computation and scoring.
  """

  require Logger

  @doc """
  Extracts structured features from a job posting.
  """
  def extract_job_features(job) do
    description_text = "#{job.title} #{job.description || ""}"

    features = %{
      # Basic info
      title: job.title,
      company: job.company,
      location: extract_location(job),
      remote_type: extract_remote_type(description_text),

      # Skills and requirements
      required_skills: extract_skills(job.description, :required),
      preferred_skills: extract_skills(job.description, :preferred),
      technical_keywords: extract_technical_keywords(description_text),

      # Experience
      experience_years_required: extract_experience_years(description_text),
      seniority_level: extract_seniority(job.title, description_text),

      # Compensation
      salary_min: extract_salary_min(job.salary),
      salary_max: extract_salary_max(job.salary),
      salary_currency: "RUB",  # Default for HH.ru

      # Company and culture
      company_culture: extract_culture_keywords(description_text),
      company_size: extract_company_size(description_text),
      benefits: extract_benefits(description_text),

      # Growth indicators
      role_level: extract_role_level(job.title),
      learning_opportunities: detect_learning_mentions(description_text),
      promotion_potential: "unknown",
      tech_stack_modern: detect_modern_tech(description_text),

      # Additional context
      job_category: categorize_job(job.title, description_text),
      keywords: extract_all_keywords(description_text),
      full_text: description_text
    }

    {:ok, features}
  end

  @doc """
  Extracts structured features from a user profile/CV.
  """
  def extract_user_features(user_profile) do
    parsed = user_profile.parsed_data || %{}

    features = %{
      # Skills
      skills: extract_user_skills(parsed),
      technical_skills: extract_user_technical_skills(parsed),
      soft_skills: extract_user_soft_skills(parsed),

      # Experience
      experience_years: calculate_experience_years(parsed),
      previous_roles: extract_previous_roles(parsed),
      industries: extract_industries(parsed),

      # Preferences
      expected_salary: user_profile[:expected_salary],
      minimum_salary: user_profile[:minimum_salary],
      preferred_locations: user_profile[:preferred_locations] || [],
      remote_preference: user_profile[:remote_preference] || "flexible",
      preferred_values: user_profile[:preferred_values] || [],
      desired_benefits: user_profile[:desired_benefits] || [],

      # Qualifications
      education_level: extract_education_level(parsed),
      certifications: extract_certifications(parsed),
      languages: extract_languages(parsed),

      # Career goals
      career_goals: user_profile[:career_goals] || [],
      willing_to_relocate: user_profile[:willing_to_relocate] || false
    }

    {:ok, features}
  end

  # Job feature extraction helpers

  defp extract_location(job) do
    # HH.ru provides area information
    job.area || "Unknown"
  end

  defp extract_remote_type(text) do
    text_lower = String.downcase(text)

    cond do
      Regex.match?(~r/удален[нo]|remote|полност[ью]?\s+удален/iu, text_lower) -> "full_remote"
      Regex.match?(~r/гибрид|hybrid|частичн[о]?\s+удален/iu, text_lower) -> "hybrid"
      Regex.match?(~r/офис|office|on-site/iu, text_lower) -> "office"
      true -> "unknown"
    end
  end

  defp extract_skills(description, type) do
    return_empty = fn -> [] end

    if is_nil(description), do: return_empty.(), else: do_extract_skills(description, type)
  end

  defp do_extract_skills(description, _type) do
    # Common programming languages and technologies
    tech_patterns = [
      ~r/\b(python|java|javascript|typescript|go|rust|ruby|php|c\+\+|c#|swift|kotlin)\b/i,
      ~r/\b(react|vue|angular|node\.?js|django|flask|spring|laravel|rails)\b/i,
      ~r/\b(postgresql|mysql|mongodb|redis|elasticsearch|kafka|rabbitmq)\b/i,
      ~r/\b(docker|kubernetes|aws|azure|gcp|terraform|jenkins|gitlab)\b/i,
      ~r/\b(machine learning|deep learning|nlp|computer vision|data science)\b/i,
      ~r/\b(rest api|graphql|microservices|agile|scrum|ci\/cd)\b/i
    ]

    skills = Enum.flat_map(tech_patterns, fn pattern ->
      Regex.scan(pattern, description)
      |> Enum.map(fn [match | _] -> String.downcase(match) end)
    end)
    |> Enum.uniq()

    skills
  end

  defp extract_technical_keywords(text) do
    # Extract common technical terms
    patterns = [
      ~r/\b(api|backend|frontend|full[- ]?stack|devops|qa|testing)\b/i,
      ~r/\b(senior|junior|lead|principal|staff|architect)\b/i,
      ~r/\b(distributed|scalable|high[- ]?load|performance|security)\b/i
    ]

    keywords = Enum.flat_map(patterns, fn pattern ->
      Regex.scan(pattern, text)
      |> Enum.map(fn [match | _] -> String.downcase(match) end)
    end)
    |> Enum.uniq()

    keywords
  end

  defp extract_experience_years(text) do
    # Try to extract experience requirements
    cond do
      Regex.match?(~r/(\d+)\+?\s*(years?|лет|год)/i, text) ->
        case Regex.run(~r/(\d+)\+?\s*(years?|лет|год)/i, text) do
          [_, years | _] -> String.to_integer(years)
          _ -> 0
        end

      Regex.match?(~r/junior|младший|стажер/i, text) -> 0
      Regex.match?(~r/middle|средний/i, text) -> 2
      Regex.match?(~r/senior|старший|ведущий/i, text) -> 5
      Regex.match?(~r/lead|тимлид|руководитель/i, text) -> 7
      true -> 0
    end
  end

  defp extract_seniority(title, description) do
    text = String.downcase("#{title} #{description}")

    cond do
      Regex.match?(~r/junior|младший|стажер|intern/i, text) -> "junior"
      Regex.match?(~r/senior|старший|ведущий/i, text) -> "senior"
      Regex.match?(~r/lead|тимлид|principal|architect|руководитель/i, text) -> "lead"
      Regex.match?(~r/middle|средний/i, text) -> "mid"
      true -> "mid"
    end
  end

  defp extract_salary_min(salary_data) when is_map(salary_data) do
    salary_data[:from] || salary_data["from"]
  end
  defp extract_salary_min(_), do: nil

  defp extract_salary_max(salary_data) when is_map(salary_data) do
    salary_data[:to] || salary_data["to"]
  end
  defp extract_salary_max(_), do: nil

  defp extract_culture_keywords(text) do
    culture_keywords = [
      "innovation", "collaboration", "growth", "learning",
      "flexible", "work-life balance", "diversity", "remote-first",
      "startup", "fast-paced", "agile", "team",
      "инновации", "развитие", "обучение", "команда"
    ]

    text_lower = String.downcase(text)

    Enum.filter(culture_keywords, fn keyword ->
      String.contains?(text_lower, String.downcase(keyword))
    end)
  end

  defp extract_company_size(text) do
    text_lower = String.downcase(text)

    cond do
      Regex.match?(~r/startup|стартап/i, text_lower) -> "startup"
      Regex.match?(~r/enterprise|корпорация/i, text_lower) -> "enterprise"
      true -> "unknown"
    end
  end

  defp extract_benefits(text) do
    benefit_patterns = [
      ~r/(medical|health|dental|vision)\s+insurance/i,
      ~r/(401k|pension|retirement)/i,
      ~r/(unlimited|flexible)\s+(pto|vacation|holiday)/i,
      ~r/stock\s+options/i,
      ~r/bonus|премия/i,
      ~r/remote\s+work/i,
      ~r/gym|fitness|спортзал/i,
      ~r/education|обучение|courses|курсы/i
    ]

    Enum.flat_map(benefit_patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [match | _] -> [String.downcase(match)]
        _ -> []
      end
    end)
  end

  defp extract_role_level(title) do
    title_lower = String.downcase(title)

    cond do
      Regex.match?(~r/lead|principal|architect|тимлид/i, title_lower) -> "lead"
      Regex.match?(~r/senior|старший/i, title_lower) -> "senior"
      Regex.match?(~r/junior|младший/i, title_lower) -> "junior"
      true -> "mid"
    end
  end

  defp detect_learning_mentions(text) do
    learning_keywords = [
      "training", "courses", "learning", "education", "conference",
      "обучение", "курсы", "развитие", "конференции"
    ]

    text_lower = String.downcase(text)

    Enum.any?(learning_keywords, fn keyword ->
      String.contains?(text_lower, keyword)
    end)
  end

  defp detect_modern_tech(text) do
    modern_tech = [
      "react", "vue", "angular", "typescript", "go", "rust",
      "kubernetes", "docker", "cloud", "microservices",
      "machine learning", "ai", "blockchain"
    ]

    text_lower = String.downcase(text)

    matches = Enum.count(modern_tech, fn tech ->
      String.contains?(text_lower, tech)
    end)

    matches >= 2
  end

  defp categorize_job(title, description) do
    text = String.downcase("#{title} #{description}")

    cond do
      Regex.match?(~r/backend|back-end|server/i, text) -> "backend"
      Regex.match?(~r/frontend|front-end|ui|ux/i, text) -> "frontend"
      Regex.match?(~r/full[- ]?stack/i, text) -> "fullstack"
      Regex.match?(~r/devops|sre|infrastructure/i, text) -> "devops"
      Regex.match?(~r/data|analytics|ml|machine learning/i, text) -> "data"
      Regex.match?(~r/mobile|ios|android/i, text) -> "mobile"
      Regex.match?(~r/qa|test|quality/i, text) -> "qa"
      Regex.match?(~r/product|manager|pm/i, text) -> "product"
      true -> "other"
    end
  end

  defp extract_all_keywords(text) do
    # Extract meaningful keywords (3+ characters, not common words)
    text
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.filter(fn word -> String.length(word) >= 3 end)
    |> Enum.uniq()
    |> Enum.take(50)  # Limit to top 50
  end

  # User feature extraction helpers

  defp extract_user_skills(parsed) do
    (parsed[:skills] || parsed["skills"] || [])
    |> List.wrap()
    |> Enum.map(&String.downcase/1)
  end

  defp extract_user_technical_skills(parsed) do
    # Filter for technical skills
    all_skills = extract_user_skills(parsed)

    tech_patterns = [
      ~r/\b(python|java|javascript|typescript|go|rust|ruby|php|c\+\+|c#)\b/i,
      ~r/\b(react|vue|angular|node|django|flask|spring)\b/i,
      ~r/\b(sql|nosql|postgresql|mysql|mongodb|redis)\b/i,
      ~r/\b(docker|kubernetes|aws|azure|gcp)\b/i
    ]

    Enum.filter(all_skills, fn skill ->
      Enum.any?(tech_patterns, fn pattern ->
        Regex.match?(pattern, skill)
      end)
    end)
  end

  defp extract_user_soft_skills(parsed) do
    all_skills = extract_user_skills(parsed)

    soft_skill_keywords = [
      "communication", "leadership", "teamwork", "problem solving",
      "critical thinking", "adaptability", "time management"
    ]

    Enum.filter(all_skills, fn skill ->
      Enum.any?(soft_skill_keywords, fn keyword ->
        String.contains?(skill, keyword)
      end)
    end)
  end

  defp calculate_experience_years(parsed) do
    experience = parsed[:experience] || parsed["experience"] || []

    # Sum up all experience durations
    Enum.reduce(experience, 0, fn exp, acc ->
      years = extract_duration_years(exp)
      acc + years
    end)
  end

  defp extract_duration_years(experience) when is_map(experience) do
    # Try to parse start and end dates
    start_date = experience[:start_date] || experience["start_date"]
    end_date = experience[:end_date] || experience["end_date"] || Date.utc_today()

    if start_date && end_date do
      # Calculate years difference
      # This is simplified - in production, parse actual dates
      2  # Default to 2 years per position
    else
      2
    end
  end
  defp extract_duration_years(_), do: 0

  defp extract_previous_roles(parsed) do
    experience = parsed[:experience] || parsed["experience"] || []

    Enum.map(experience, fn exp ->
      exp[:title] || exp["title"] || "Unknown"
    end)
  end

  defp extract_industries(parsed) do
    experience = parsed[:experience] || parsed["experience"] || []

    Enum.map(experience, fn exp ->
      exp[:industry] || exp["industry"]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp extract_education_level(parsed) do
    education = parsed[:education] || parsed["education"] || []

    levels = Enum.map(education, fn edu ->
      degree = edu[:degree] || edu["degree"] || ""
      degree_lower = String.downcase(degree)

      cond do
        String.contains?(degree_lower, "phd") -> 5
        String.contains?(degree_lower, "master") -> 4
        String.contains?(degree_lower, "bachelor") -> 3
        String.contains?(degree_lower, "associate") -> 2
        true -> 1
      end
    end)

    case Enum.max(levels, fn -> 0 end) do
      5 -> "phd"
      4 -> "masters"
      3 -> "bachelors"
      2 -> "associates"
      _ -> "none"
    end
  end

  defp extract_certifications(parsed) do
    (parsed[:certifications] || parsed["certifications"] || [])
    |> List.wrap()
  end

  defp extract_languages(parsed) do
    (parsed[:languages] || parsed["languages"] || [])
    |> List.wrap()
  end
end
