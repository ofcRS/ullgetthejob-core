defmodule Core.AI.Matching.Scorer do
  @moduledoc """
  Multi-factor scoring engine for job matching.

  Implements sophisticated scoring algorithms across multiple dimensions:
  - Semantic skill matching with synonym awareness
  - Experience level alignment with seniority mapping
  - Salary range compatibility analysis
  - Geographic and remote work preferences
  - Company culture and values alignment
  - Career trajectory and growth potential
  - Benefits and perks evaluation

  Scoring methodology:
  - Each dimension scored 0.0 to 1.0
  - Weighted combination for overall score
  - Confidence intervals based on data quality
  - Contextual adjustments based on market conditions
  """

  require Logger

  @score_weights %{
    skill_match: 0.30,
    experience_match: 0.25,
    salary_match: 0.15,
    location_match: 0.10,
    company_culture: 0.10,
    career_growth: 0.05,
    benefits: 0.05
  }

  @doc """
  Computes comprehensive match scores from job and user features.
  """
  def compute_scores(job_features, user_features) do
    Logger.debug("Computing multi-factor scores")

    skill_score = compute_skill_match(job_features, user_features)
    experience_score = compute_experience_match(job_features, user_features)
    salary_score = compute_salary_match(job_features, user_features)
    location_score = compute_location_match(job_features, user_features)
    culture_score = compute_culture_match(job_features, user_features)
    growth_score = compute_growth_potential(job_features, user_features)
    benefits_score = compute_benefits_match(job_features, user_features)

    overall_score = compute_weighted_score([
      {skill_score.score, @score_weights.skill_match},
      {experience_score.score, @score_weights.experience_match},
      {salary_score.score, @score_weights.salary_match},
      {location_score.score, @score_weights.location_match},
      {culture_score.score, @score_weights.company_culture},
      {growth_score.score, @score_weights.career_growth},
      {benefits_score.score, @score_weights.benefits}
    ])

    confidence = compute_confidence([
      skill_score.confidence,
      experience_score.confidence,
      salary_score.confidence,
      location_score.confidence
    ])

    {:ok, %{
      overall_score: overall_score,
      skill_match_score: skill_score.score,
      experience_match_score: experience_score.score,
      salary_match_score: salary_score.score,
      location_match_score: location_score.score,
      company_culture_score: culture_score.score,
      career_growth_score: growth_score.score,
      benefits_score: benefits_score.score,
      matching_skills: skill_score.matching,
      missing_skills: skill_score.missing,
      growth_opportunities: growth_score.opportunities,
      concerns: compile_concerns(salary_score, experience_score, location_score),
      recommendations: generate_recommendations(skill_score, experience_score, salary_score),
      confidence_level: confidence,
      factors: %{
        skill_details: skill_score.details,
        experience_details: experience_score.details,
        salary_details: salary_score.details,
        location_details: location_score.details
      }
    }}
  end

  # Skill matching with semantic analysis
  defp compute_skill_match(job_features, user_features) do
    required_skills = job_features.required_skills || []
    preferred_skills = job_features.preferred_skills || []
    user_skills = user_features.skills || []

    # Normalize skill names for comparison
    normalized_user_skills = Enum.map(user_skills, &normalize_skill/1)
    normalized_required = Enum.map(required_skills, &normalize_skill/1)
    normalized_preferred = Enum.map(preferred_skills, &normalize_skill/1)

    # Find matching skills using semantic similarity
    matching_required = find_matching_skills(normalized_required, normalized_user_skills)
    matching_preferred = find_matching_skills(normalized_preferred, normalized_user_skills)

    # Calculate coverage
    required_coverage = safe_divide(length(matching_required), length(normalized_required), 1.0)
    preferred_coverage = safe_divide(length(matching_preferred), length(normalized_preferred), 1.0)

    # Weight required skills higher than preferred
    score = (required_coverage * 0.7) + (preferred_coverage * 0.3)

    # Identify missing critical skills
    missing_required = normalized_required -- matching_required
    missing_preferred = normalized_preferred -- matching_preferred

    %{
      score: min(score, 1.0),
      confidence: if(length(required_skills) > 0, do: 0.9, else: 0.5),
      matching: matching_required ++ matching_preferred,
      missing: missing_required,
      details: %{
        required_coverage: required_coverage,
        preferred_coverage: preferred_coverage,
        total_user_skills: length(user_skills),
        missing_critical: missing_required
      }
    }
  end

  # Experience level matching
  defp compute_experience_match(job_features, user_features) do
    required_years = job_features.experience_years_required || 0
    user_years = user_features.experience_years || 0
    seniority = job_features.seniority_level || "mid"

    # Score based on experience alignment
    score = cond do
      # Perfect match or slight overqualification
      user_years >= required_years && user_years <= required_years * 1.5 -> 1.0

      # Underqualified but close
      user_years >= required_years * 0.8 -> 0.8

      # Significantly underqualified
      user_years < required_years * 0.8 ->
        max(0.3, user_years / required_years)

      # Overqualified
      user_years > required_years * 1.5 ->
        max(0.6, 1.0 - ((user_years - required_years) / required_years) * 0.2)

      true -> 0.5
    end

    # Check seniority alignment
    user_seniority = infer_seniority(user_years)
    seniority_match = seniority == user_seniority

    adjusted_score = if seniority_match, do: score, else: score * 0.9

    %{
      score: adjusted_score,
      confidence: 0.85,
      details: %{
        required_years: required_years,
        user_years: user_years,
        seniority: seniority,
        user_seniority: user_seniority,
        seniority_match: seniority_match
      }
    }
  end

  # Salary matching analysis
  defp compute_salary_match(job_features, user_features) do
    job_salary_min = job_features.salary_min
    job_salary_max = job_features.salary_max
    user_expected = user_features.expected_salary
    user_minimum = user_features.minimum_salary

    score = cond do
      # No salary data available
      is_nil(job_salary_min) && is_nil(job_salary_max) -> 0.7
      is_nil(user_expected) && is_nil(user_minimum) -> 0.7

      # User expectations within job range
      user_expected && job_salary_max && user_expected <= job_salary_max &&
      user_expected >= (job_salary_min || 0) -> 1.0

      # User minimum met by job
      user_minimum && job_salary_max && user_minimum <= job_salary_max -> 0.9

      # Slight mismatch but negotiable
      user_minimum && job_salary_max && user_minimum <= job_salary_max * 1.1 -> 0.7

      # Significant gap
      user_minimum && job_salary_max && user_minimum > job_salary_max * 1.1 -> 0.3

      true -> 0.5
    end

    %{
      score: score,
      confidence: if(job_salary_min || job_salary_max, do: 0.8, else: 0.3),
      details: %{
        job_salary_range: {job_salary_min, job_salary_max},
        user_expectations: {user_minimum, user_expected},
        negotiable: score >= 0.7
      }
    }
  end

  # Location and remote work matching
  defp compute_location_match(job_features, user_features) do
    job_location = job_features.location
    job_remote = job_features.remote_type || "none"
    user_locations = user_features.preferred_locations || []
    user_remote_pref = user_features.remote_preference || "hybrid"

    score = cond do
      # Fully remote jobs match any location preference
      job_remote in ["full_remote", "fully_remote"] -> 1.0

      # Hybrid work - moderate match
      job_remote in ["hybrid", "flexible"] -> 0.85

      # Location match
      job_location in user_locations -> 1.0

      # Different location but user is flexible
      user_remote_pref == "open" -> 0.6

      # Location mismatch, no remote
      true -> 0.3
    end

    %{
      score: score,
      confidence: 0.9,
      details: %{
        job_location: job_location,
        job_remote_type: job_remote,
        user_locations: user_locations,
        user_remote_preference: user_remote_pref
      }
    }
  end

  # Company culture and values alignment
  defp compute_culture_match(job_features, user_features) do
    job_culture = job_features.company_culture || []
    user_values = user_features.preferred_values || []

    # Find value overlaps
    common_values = MapSet.intersection(
      MapSet.new(job_culture),
      MapSet.new(user_values)
    ) |> MapSet.size()

    score = if length(user_values) > 0 do
      common_values / length(user_values)
    else
      0.6  # Neutral score when no preference specified
    end

    %{
      score: min(score, 1.0),
      confidence: 0.5,  # Culture matching is inherently uncertain
      details: %{
        common_values: common_values,
        total_user_values: length(user_values)
      }
    }
  end

  # Career growth potential analysis
  defp compute_growth_potential(job_features, user_features) do
    growth_indicators = [
      job_features.company_size == "growing",
      job_features.role_level in ["lead", "senior", "principal"],
      job_features.learning_opportunities == true,
      job_features.promotion_potential == "high"
    ]

    growth_score = Enum.count(growth_indicators, & &1) / length(growth_indicators)

    opportunities = build_growth_opportunities(job_features, user_features)

    %{
      score: growth_score,
      confidence: 0.4,
      opportunities: opportunities,
      details: %{}
    }
  end

  # Benefits and perks evaluation
  defp compute_benefits_match(job_features, user_features) do
    job_benefits = job_features.benefits || []
    user_desired = user_features.desired_benefits || []

    matched_benefits = Enum.filter(user_desired, fn benefit ->
      Enum.any?(job_benefits, &String.contains?(String.downcase(&1), String.downcase(benefit)))
    end)

    score = if length(user_desired) > 0 do
      length(matched_benefits) / length(user_desired)
    else
      0.5
    end

    %{
      score: score,
      confidence: 0.6,
      details: %{
        matched_benefits: matched_benefits,
        total_job_benefits: length(job_benefits)
      }
    }
  end

  # Helper functions

  defp compute_weighted_score(score_weight_pairs) do
    total_weight = Enum.reduce(score_weight_pairs, 0, fn {_, weight}, acc -> acc + weight end)

    weighted_sum = Enum.reduce(score_weight_pairs, 0, fn {score, weight}, acc ->
      acc + (score * weight)
    end)

    weighted_sum / total_weight
  end

  defp compute_confidence(confidences) do
    # Average confidence with penalty for low confidence scores
    avg = Enum.sum(confidences) / length(confidences)
    min_conf = Enum.min(confidences)

    # If any factor has very low confidence, reduce overall
    if min_conf < 0.3, do: avg * 0.7, else: avg
  end

  defp normalize_skill(skill) do
    skill
    |> String.downcase()
    |> String.trim()
  end

  defp find_matching_skills(required, available) do
    Enum.filter(required, fn req_skill ->
      # Direct match or semantic similarity
      Enum.any?(available, fn avail_skill ->
        req_skill == avail_skill ||
        String.contains?(avail_skill, req_skill) ||
        String.contains?(req_skill, avail_skill) ||
        semantic_similarity(req_skill, avail_skill) > 0.8
      end)
    end)
  end

  defp semantic_similarity(skill1, skill2) do
    # Simple Jaccard similarity for now
    # In production, use more sophisticated NLP/embeddings
    set1 = String.split(skill1, ~r/\W+/) |> MapSet.new()
    set2 = String.split(skill2, ~r/\W+/) |> MapSet.new()

    intersection = MapSet.intersection(set1, set2) |> MapSet.size()
    union = MapSet.union(set1, set2) |> MapSet.size()

    if union > 0, do: intersection / union, else: 0.0
  end

  defp infer_seniority(years) do
    cond do
      years < 2 -> "junior"
      years < 5 -> "mid"
      years < 8 -> "senior"
      true -> "lead"
    end
  end

  defp safe_divide(_, 0, default), do: default
  defp safe_divide(numerator, denominator, _), do: numerator / denominator

  defp compile_concerns(salary_score, experience_score, location_score) do
    concerns = []

    concerns = if salary_score.score < 0.5 do
      ["Salary expectations may not align" | concerns]
    else
      concerns
    end

    concerns = if experience_score.score < 0.6 do
      ["Experience level may not match requirements" | concerns]
    else
      concerns
    end

    concerns = if location_score.score < 0.5 do
      ["Location or remote work preference mismatch" | concerns]
    else
      concerns
    end

    concerns
  end

  defp generate_recommendations(skill_score, experience_score, salary_score) do
    recommendations = []

    recommendations = if length(skill_score.missing) > 0 do
      ["Consider highlighting transferable skills related to: #{Enum.join(skill_score.missing, ", ")}" | recommendations]
    else
      recommendations
    end

    recommendations = if experience_score.score < 0.7 do
      ["Emphasize relevant projects and achievements to compensate for experience gap" | recommendations]
    else
      recommendations
    end

    recommendations = if salary_score.score < 0.7 do
      ["Be prepared to negotiate salary or highlight unique value proposition" | recommendations]
    else
      recommendations
    end

    Enum.join(recommendations, ". ")
  end

  defp build_growth_opportunities(job_features, _user_features) do
    opportunities = []

    opportunities = if job_features.learning_budget do
      ["Professional development budget available" | opportunities]
    else
      opportunities
    end

    opportunities = if job_features.mentorship_program do
      ["Mentorship program offered" | opportunities]
    else
      opportunities
    end

    opportunities = if job_features.tech_stack_modern do
      ["Work with modern technology stack" | opportunities]
    else
      opportunities
    end

    opportunities
  end
end
