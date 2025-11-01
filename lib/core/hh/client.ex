defmodule Core.HH.Client do
  @moduledoc """
  Minimal HH.ru API client for fetching vacancies.

  Authentication: Bearer token from env `HH_ACCESS_TOKEN`.
  """

  require Logger

  @base_url "https://api.hh.ru"

  defp user_agent do
    System.get_env("HH_USER_AGENT") || "UllGetTheJob/1.0"
  end

  defp hh_headers(access_token) do
    [{"Authorization", "Bearer #{access_token}"}, {"Accept", "application/json"}, {"User-Agent", user_agent()}]
  end

  @doc """
  Fetch vacancies from HH.ru using supported params.

  Supported params:
  - :text, :area, :experience, :employment, :schedule

  Returns {:ok, [job, ...]} or {:error, reason}
  """
  @spec fetch_vacancies(map()) :: {:ok, list(map())} | {:error, any()}
  def fetch_vacancies(params \\ %{}) do
    token = System.get_env("HH_ACCESS_TOKEN")
    headers =
      case token do
        nil -> []
        "" -> []
        token -> [{"Authorization", "Bearer #{token}"}]
      end

    query =
      params
      |> Map.take([:text, :area, :experience, :employment, :schedule])
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Enum.into(%{})

    case Req.get("#{@base_url}/vacancies", headers: headers, params: query) do
      {:ok, %{status: 200, body: body}} ->
        data = decode_body(body)
        items = Map.get(data, "items", [])
        {:ok, Enum.map(items, &normalize_vacancy/1)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("HH API error status=#{status} body=#{log_term(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("HH API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetch authenticated user's resumes using access token.
  GET /resumes/mine
  """
  @spec fetch_user_resumes(binary()) :: {:ok, list(map())} | {:error, any()}
  def fetch_user_resumes(access_token) when is_binary(access_token) do
    case Req.get("#{@base_url}/resumes/mine", headers: hh_headers(access_token)) do
      {:ok, %{status: 200, body: body}} ->
        data = decode_body(body)
        {:ok, Map.get(data, "items", [])}
      {:ok, %{status: status, body: body}} ->
        Logger.error("HH API resumes error status=#{status} body=#{log_term(body)}")
        {:error, {:http_error, status}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetch full vacancy details by id.
  GET /vacancies/:id
  """
  @spec fetch_vacancy_details(binary()) :: {:ok, map()} | {:error, any()}
  def fetch_vacancy_details(vacancy_id) when is_binary(vacancy_id) do
    token = System.get_env("HH_ACCESS_TOKEN")
    headers =
      case token do
        nil -> []
        "" -> []
        token -> [{"Authorization", "Bearer #{token}"}]
      end

    case Req.get("#{@base_url}/vacancies/#{vacancy_id}", headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, decode_body(body)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("HH API vacancy details error status=#{status} body=#{log_term(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("HH API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetch resume details by id.
  GET /resumes/:id
  """
  @spec fetch_resume_details(binary(), binary()) :: {:ok, map()} | {:error, any()}
  def fetch_resume_details(resume_id, access_token) when is_binary(resume_id) and is_binary(access_token) do
    case Req.get("#{@base_url}/resumes/#{resume_id}", headers: hh_headers(access_token)) do
      {:ok, %{status: 200, body: body}} -> {:ok, decode_body(body)}
      {:ok, %{status: status, body: body}} ->
        Logger.error("HH API resume details error status=#{status} body=#{log_term(body)}")
        {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_body(%{} = body), do: body
  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} -> map
      _ -> %{}
    end
  end

  defp normalize_vacancy(item) do
    %{
      hh_vacancy_id: item["id"],
      id: item["id"],
      title: item["name"],
      company: get_in(item, ["employer", "name"]),
      salary: render_salary(item["salary"]),
      area: get_in(item, ["area", "name"]),
      url: item["alternate_url"],
      skills: [],
      description: build_description(item),
      has_test: Map.get(item, "has_test", false),
      test_required: Map.get(item, "has_test", false)
    }
  end

  defp render_salary(nil), do: nil
  defp render_salary(%{"from" => from, "to" => to, "currency" => currency}) do
    cond do
      from && to -> "#{from}-#{to} #{currency}"
      from -> "from #{from} #{currency}"
      to -> "to #{to} #{currency}"
      true -> nil
    end
  end
  defp render_salary(_), do: nil

  defp build_description(item) do
    req = get_in(item, ["snippet", "requirement"]) || ""
    resp = get_in(item, ["snippet", "responsibility"]) || ""
    [req, resp]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> String.trim()
  end

  @doc """
  Ensure a resume exists for the user and return its id, creating one if necessary.
  """
  @spec get_or_create_resume(binary(), map()) :: {:ok, binary()} | {:error, any()}
  def get_or_create_resume(access_token, customized_cv) when is_binary(access_token) do
    cond do
      resume_id = extract_resume_id(customized_cv) ->
        Logger.info("Using provided HH resume id from customized_cv: len=#{String.length(resume_id)}")
        # If caller provided an existing resume id, make sure minimal required fields exist
        _ = ensure_existing_resume_completeness(access_token, resume_id, customized_cv)
        {:ok, resume_id}

      true ->
        headers = hh_headers(access_token)

        with {:ok, payload} <- build_resume_payload(customized_cv) do
          Logger.debug("HH resume payload: " <> resume_payload_summary(payload))

          title = Map.get(payload, :title)

          case find_existing_resume_by_title(access_token, to_string(title || "")) do
            {:ok, existing_id} ->
              Logger.info("Using existing HH resume by title: id=#{existing_id} title=#{inspect(title)}")
              _ = ensure_existing_resume_completeness(access_token, existing_id, customized_cv)
              ensure_resume_ready(access_token, existing_id)
              {:ok, existing_id}

            _ ->
              case Req.post("#{@base_url}/resumes", headers: headers, json: payload) do
                {:ok, resp = %{status: status}} when status in [200, 201] ->
                  case extract_resume_id_from_response(resp) do
                    nil ->
                      # Some HH responses omit id and Location; try to locate by title
                      case find_existing_resume_by_title(access_token, to_string(title || "")) do
                        {:ok, id} ->
                          Logger.info("HH created resume (lookup): id=#{id} title=#{inspect(title)}")
                          ensure_resume_ready(access_token, id)
                          {:ok, id}
                        _ ->
                          Logger.error("HH created resume but missing id and lookup failed for title=#{inspect(title)}")
                          {:error, :missing_resume_id}
                      end
                    id ->
                      Logger.info("HH created resume: id=#{id} location=#{inspect(get_header(resp, "location"))}")
                      ensure_resume_ready(access_token, id)
                      {:ok, id}
                  end

                {:ok, %{status: 400, body: body}} ->
                  if duplicate_title_error?(body) do
                    case find_existing_resume_by_title(access_token, to_string(title || "")) do
                      {:ok, id} -> {:ok, id}
                      _ ->
                        unique_title = uniquify_title(to_string(title || "Resume"))
                        payload2 = Map.put(payload, :title, unique_title)

                        case Req.post("#{@base_url}/resumes", headers: headers, json: payload2) do
                          {:ok, resp = %{status: status}} when status in [200, 201] ->
                            case extract_resume_id_from_response(resp) do
                              nil ->
                                case find_existing_resume_by_title(access_token, to_string(unique_title || "")) do
                                  {:ok, id} ->
                                    Logger.info("HH created resume (retry+lookup): id=#{id} title=#{inspect(unique_title)}")
                                    ensure_resume_ready(access_token, id)
                                    {:ok, id}
                                  _ ->
                                    Logger.error("HH created resume (retry) but missing id and lookup failed for title=#{inspect(unique_title)}")
                                    {:error, :missing_resume_id}
                                end
                              id ->
                                Logger.info("HH created resume (retry): id=#{id} location=#{inspect(get_header(resp, "location"))}")
                                ensure_resume_ready(access_token, id)
                                {:ok, id}
                            end

                          {:ok, %{status: status, body: body}} ->
                  Logger.error("HH API create resume (retry) error status=#{status} body=#{log_term(body)}")
                            {:error, {:http_error, status, body}}

                          {:error, reason} ->
                            Logger.error("HH API create resume (retry) request failed: #{inspect(reason)}")
                            {:error, reason}
                        end
                    end
                  else
                Logger.error("HH API create resume error status=400 body=#{log_term(body)}")
                    {:error, {:http_error, 400, body}}
                  end

                {:ok, %{status: status, body: body}} ->
                  Logger.error("HH API create resume error status=#{status} body=#{log_term(body)}")
                  {:error, {:http_error, status, body}}

                {:error, reason} ->
                  Logger.error("HH API create resume request failed: #{inspect(reason)}")
                  {:error, reason}
              end
          end
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Publish resume on HH.ru.
  """
  @spec publish_resume(binary(), binary()) :: :ok | {:error, any()}
  def publish_resume(access_token, resume_id) when is_binary(access_token) and is_binary(resume_id) do
    case Req.post("#{@base_url}/resumes/#{resume_id}/publish", headers: hh_headers(access_token)) do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{status: 404}} ->
        # Some accounts may not require explicit publish or endpoint may vary; proceed.
        :ok
      {:ok, %{status: 400, body: body}} ->
        # HH may return "Can't publish resume" when publication isn't applicable; proceed.
        map = decode_body(body)
        desc = Map.get(map, "description") |> to_string()
        if String.contains?(String.downcase(desc), "can't publish") do
          :ok
        else
          Logger.error("HH API publish resume error status=400 body=#{log_term(body)}")
          {:error, {:http_error, 400, body}}
        end
      {:ok, %{status: status, body: body}} ->
        Logger.error("HH API publish resume error status=#{status} body=#{log_term(body)}")
        {:error, {:http_error, status, body}}
      {:error, reason} ->
        Logger.error("HH API publish resume request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Submit application to HH.ru.
  """
  @spec submit_application(binary(), binary(), binary(), binary() | nil) :: {:ok, binary()} | {:error, any()}
  def submit_application(access_token, job_external_id, resume_id, cover_letter)
      when is_binary(access_token) and is_binary(job_external_id) and is_binary(resume_id) do
    if String.trim(resume_id) == "" do
      Logger.error("Attempted to submit application with blank resume_id")
      {:error, :missing_resume_id}
    else
      auth_headers = hh_headers(access_token)

      json_headers = auth_headers ++ [{"Content-Type", "application/json"}]
      json_payload = %{
        vacancy_id: job_external_id,
        resume_id: resume_id,
        message: cover_letter || ""
      }

      Logger.debug("Negotiation attempt(JSON): vacancy_id_present=#{job_external_id not in [nil, ""]} resume_id_len=#{String.length(resume_id)}")

      with {:json_attempt, {:ok, result}} <- {:json_attempt, do_negotiation_json(json_headers, json_payload)} do
        {:ok, result}
      else
        {:json_attempt, {:error, {:bad_arguments, body}}} ->
          # Retry using form-encoded body expected by some HH endpoints
          case do_negotiation_form(auth_headers, job_external_id, resume_id, cover_letter) do
            {:ok, id} -> {:ok, id}
            {:error, {:http_error, 400, body}} = err ->
              if resume_not_found_reason?(body) do
                Logger.debug("Negotiation resume_not_found; waiting and retrying...")
                wait_and_retry_negotiation(auth_headers, job_external_id, resume_id, cover_letter, 8)
              else
                err
              end
            other -> other
          end

        {:json_attempt, other} ->
          other
      end
    end
  end

  defp wait_and_retry_negotiation(headers, job_external_id, resume_id, cover_letter, attempts) when attempts > 0 do
    Process.sleep(1500)
    case do_negotiation_form(headers, job_external_id, resume_id, cover_letter) do
      {:ok, id} -> {:ok, id}
      {:error, {:http_error, 400, body}} ->
        if resume_not_found_reason?(body) do
          Logger.debug("Negotiation retry remaining=#{attempts - 1} resume_id_len=#{String.length(resume_id)}")
          wait_and_retry_negotiation(headers, job_external_id, resume_id, cover_letter, attempts - 1)
        else
          {:error, {:http_error, 400, body}}
        end
      other -> other
    end
  end
  defp wait_and_retry_negotiation(_headers, _job_external_id, _resume_id, _cover_letter, _attempts), do: {:error, :resume_not_available}

  defp resume_not_found_reason?(body) do
    map = decode_body(body)
    by_error_value =
      map
      |> Map.get("errors", [])
      |> List.wrap()
      |> Enum.any?(fn e -> (Map.get(e, "value") || Map.get(e, :value)) == "resume_not_found" end)

    by_desc =
      map
      |> Map.get("description")
      |> to_string()
      |> String.downcase()
      |> (fn s -> String.contains?(s, "resume not found") or String.contains?(s, "not available") end).()

    by_bad_arg = (Map.get(map, "bad_argument") || Map.get(map, :bad_argument)) == "resume_id"

    by_error_value or (by_desc and by_bad_arg)
  end

  defp do_negotiation_json(headers, payload) do
    case Req.post("#{@base_url}/negotiations", headers: headers, json: payload) do
      {:ok, %{status: status, body: body}} when status in [200, 201] ->
        body |> decode_body() |> Map.get("id") |> case do
          nil -> {:error, :missing_negotiation_id}
          id -> {:ok, id}
        end
      {:ok, %{status: 403, body: body}} -> {:error, {:forbidden, decode_body(body)}}
      {:ok, %{status: 400, body: body}} ->
        map = decode_body(body)
        bads = Map.get(map, "bad_arguments", [])
        names = Enum.map(bads, &Map.get(&1, "name"))
        if Enum.any?(names, &(&1 in ["vacancy_id", "resume_id"])) do
          Logger.info("HH negotiations JSON rejected; falling back to form. missing=#{inspect(names)} desc=#{Map.get(map, "description")}")
          {:error, {:bad_arguments, body}}
        else
          {:error, {:http_error, 400, body}}
        end
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_negotiation_form(headers, job_external_id, resume_id, cover_letter) do
    form = [vacancy_id: job_external_id, resume_id: resume_id, message: cover_letter || ""]
    Logger.debug("Negotiation attempt(FORM): vacancy_id_present=#{job_external_id not in [nil, ""]} resume_id_len=#{String.length(resume_id)}")
    case Req.post("#{@base_url}/negotiations", headers: headers, form: form) do
      {:ok, %{status: status, body: body}} when status in [200, 201] ->
        body |> decode_body() |> Map.get("id") |> case do
          nil -> {:error, :missing_negotiation_id}
          id -> {:ok, id}
        end
      {:ok, %{status: 403, body: body}} ->
        Logger.error("HH negotiations FORM forbidden: body=#{log_term(body)}")
        {:error, {:forbidden, decode_body(body)}}
      {:ok, %{status: status, body: body}} ->
        Logger.error("HH negotiations FORM error status=#{status} body=#{log_term(body)}")
        {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_resume_id(customized_cv) when is_map(customized_cv) do
    val = customized_cv["hh_resume_id"] || customized_cv[:hh_resume_id]
    case val do
      s when is_binary(s) ->
        s = String.trim(s)
        if s == "", do: nil, else: s
      _ -> nil
    end
  end

  defp extract_resume_id(_), do: nil

  defp build_resume_payload(customized_cv) do
    with {:ok, contacts} <- build_contact(customized_cv),
         skills_text <- build_skills(Map.get(customized_cv, "skills")),
         experience <- build_experience_sections(Map.get(customized_cv, "experience"), customized_cv),
         education <- build_education_sections(Map.get(customized_cv, "education")) do
      payload = %{
        title: Map.get(customized_cv, "title") || "Resume",
        first_name: Map.get(customized_cv, "firstName") || Map.get(customized_cv, "first_name") || "",
        last_name: Map.get(customized_cv, "lastName") || Map.get(customized_cv, "last_name") || "",
        summary: Map.get(customized_cv, "summary") || Map.get(customized_cv, "about")
      }
      |> maybe_put(:area, build_area(customized_cv))
      |> maybe_put(:contact, contacts)
      |> maybe_put(:skills, skills_text)
      |> maybe_put(:experience, experience)
      |> maybe_put(:education, education)

      {:ok, payload}
    end
  end

  defp build_contact(customized_cv) do
    email = customized_cv |> Map.get("email") |> normalize_email()
    phone = customized_cv |> Map.get("phone") |> normalize_phone()

    cond do
      is_nil(email) -> {:error, :missing_email}
      is_nil(phone) -> {:error, :missing_phone}
      true ->
        contacts = [build_email_contact(email)] ++ build_phone_contacts(phone)
        {:ok, contacts}
    end
  end

  defp build_skills(nil), do: nil
  defp build_skills(skills) when is_list(skills) do
    cleaned =
      skills
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if cleaned == [] do
      nil
    else
      Enum.join(cleaned, "\n")
    end
  end

  defp build_skills(skills) when is_binary(skills) do
    skills
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      list -> Enum.join(list, "\n")
    end
  end

  defp build_skills(_), do: nil

  defp build_experience_sections(nil, _cv), do: nil
  defp build_experience_sections(experience, customized_cv) when is_list(experience) do
    Enum.map(experience, fn entry ->
      %{
        "company" => Map.get(entry, "company") || Map.get(entry, "employer") || Map.get(entry, "organization") || default_company(customized_cv),
        "position" => Map.get(entry, "position") || Map.get(entry, "role") || default_position(customized_cv),
        "description" => Map.get(entry, "description") || Map.get(entry, "summary") || build_experience_description(entry),
        "start" => Map.get(entry, "start") || format_year_month_back_one_year(),
        "end" => Map.get(entry, "end")
      }
    end)
    |> Enum.filter(&valid_experience?/1)
    |> case do
      [] -> nil
      list -> list
    end
  end

  defp build_experience_sections(experience, customized_cv) when is_binary(experience) do
    text = String.trim(experience)

    if text == "" do
      nil
    else
      [%{
        "company" => default_company(customized_cv),
        "position" => default_position(customized_cv),
        "description" => text,
        "start" => format_year_month_back_one_year(),
        "end" => nil
      }]
    end
  end

  defp build_experience_sections(_, _), do: nil

  defp build_experience_description(entry) do
    entry
    |> Map.values()
    |> Enum.map(&to_string/1)
    |> Enum.join(" \u2014 ")
    |> String.trim()
  end

  defp valid_experience?(%{"position" => position, "description" => desc}) do
    String.trim(to_string(position)) != "" or String.trim(to_string(desc)) != ""
  end
  defp valid_experience?(_), do: false

  defp build_education_sections(nil) do
    %{
      "level" => %{"id" => "higher"},
      "primary" => []
    }
  end
  defp build_education_sections(education) when is_list(education) do
    primary =
      education
      |> Enum.map(&normalize_education_entry/1)
      |> Enum.reject(&is_nil/1)

    %{
      "level" => %{"id" => "higher"},
      "primary" => primary
    }
  end

  defp build_education_sections(education) when is_binary(education) do
    text = String.trim(education)

    if text == "" do
      %{"level" => %{"id" => "higher"}, "primary" => []}
    else
      %{
        "level" => %{"id" => "higher"},
        "primary" => [%{"name" => text, "year" => current_year()}]
      }
    end
  end

  defp build_education_sections(%{} = education) do
    level = get_in(education, ["level", "id"]) || get_in(education, [:level, :id]) || "higher"
    primary =
      education
      |> Map.get("primary")
      |> case do
        nil -> []
        list when is_list(list) ->
          list
          |> Enum.map(&normalize_education_entry/1)
          |> Enum.reject(&is_nil/1)
        other when is_binary(other) -> [%{"name" => String.trim(other), "year" => current_year()}]
        _ -> []
      end

    %{
      "level" => %{"id" => level},
      "primary" => primary
    }
  end

  defp build_education_sections(_), do: %{"level" => %{"id" => "higher"}, "primary" => []}

  defp normalize_education_entry(entry) when is_map(entry) do
    name = Map.get(entry, "name") || Map.get(entry, "institution") || Map.get(entry, "school")
    year = Map.get(entry, "year") || Map.get(entry, "graduation_year") || current_year()
    result = Map.get(entry, "result")

    cond do
      is_nil(name) or String.trim(to_string(name)) == "" -> nil
      true ->
        base = %{"name" => name, "year" => year}
        |> maybe_put("result", result)

        base
    end
  end

  defp normalize_education_entry(entry) when is_binary(entry) do
    text = String.trim(entry)
    if text == "", do: nil, else: %{"name" => text, "year" => current_year()}
  end

  defp normalize_education_entry(_), do: nil

  defp current_year do
    DateTime.utc_now().year
  end

  defp format_year_month_back_one_year do
    date = Date.utc_today() |> Date.add(-365)
    year = Integer.to_string(date.year)
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    year <> "-" <> month <> "-01"
  end

  defp normalize_email(nil), do: nil
  defp normalize_email(email) when is_binary(email) do
    email = String.trim(email)
    if email == "" or not String.contains?(email, "@"), do: nil, else: email
  end
  defp normalize_email(_), do: nil

  defp normalize_phone(nil), do: nil
  defp normalize_phone(phone) when is_binary(phone) do
    formatted = String.trim(phone)
    digits = String.replace(formatted, ~r/[^\d]/, "")

    if String.length(digits) < 7 do
      nil
    else
      %{
        "digits" => digits,
        "formatted" => formatted
      }
    end
  end
  defp normalize_phone(_), do: nil

  defp build_email_contact(email) do
    %{
      "type" => %{"id" => "email"},
      "kind" => "email",
      "value" => email,
      "preferred" => true
    }
  end

  defp build_phone_contacts(phone) do
    country = derive_country_code(phone["digits"])
    {city, number} = split_city_number(phone["digits"], country)

    value =
      %{"formatted" => phone["formatted"]}
      |> maybe_put("country", country)
      |> maybe_put("city", city)
      |> maybe_put("number", number)

    [
      %{
        "type" => %{"id" => "cell"},
        "kind" => "phone",
        "value" => value,
        "preferred" => false,
        "need_verification" => false,
        "verified" => false
      }
    ]
  end

  defp derive_country_code(digits) do
    cond do
      String.length(digits) > 10 -> String.slice(digits, 0, String.length(digits) - 10)
      true -> "7"
    end
  end

  defp split_city_number(digits, country_code) do
    trimmed = String.trim_leading(digits, country_code)

    cond do
      String.length(trimmed) >= 10 ->
        city = String.slice(trimmed, 0, 3)
        number = String.slice(trimmed, 3, 7)
        {city, number}

      String.length(trimmed) > 7 ->
        split_at = String.length(trimmed) - 7
        city = String.slice(trimmed, 0, split_at)
        number = String.slice(trimmed, split_at, 7)
        {city, number}

      true ->
        {String.slice(trimmed, 0, 3) || "", String.slice(trimmed, 3, 7) || trimmed}
    end
  end

  defp default_company(customized_cv) do
    Map.get(customized_cv, "currentCompany") || Map.get(customized_cv, "company") || "Self-employed"
  end

  defp default_position(customized_cv) do
    Map.get(customized_cv, "title") || "Specialist"
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp build_area(customized_cv) do
    area = Map.get(customized_cv, "area") || Map.get(customized_cv, "area_id") || Map.get(customized_cv, "location")

    cond do
      is_binary(area) and String.trim(area) != "" -> %{"id" => area}
      is_map(area) and Map.has_key?(area, "id") -> %{"id" => to_string(area["id"])}
      is_map(area) and Map.has_key?(area, :id) -> %{"id" => to_string(area[:id])}
      true -> %{"id" => "1"}
    end
  end

  defp find_existing_resume_by_title(access_token, title) when is_binary(title) do
    case fetch_user_resumes(access_token) do
      {:ok, items} ->
        down = String.downcase(String.trim(title))
        items
        |> Enum.find(fn r -> String.downcase(to_string(r["title"] || "")) == down end)
        |> case do
          %{"id" => id} -> {:ok, id}
          _ -> :not_found
        end
      error -> error
    end
  end
  defp find_existing_resume_by_title(_access_token, _title), do: :not_found

  defp duplicate_title_error?(body) do
    map = decode_body(body)
    bad = Map.get(map, "bad_argument")
    errs = Map.get(map, "errors", [])

    bad == "title" or
      Enum.any?(errs, fn e ->
        pointer = Map.get(e, "pointer")
        reason = Map.get(e, "reason")
        (pointer in ["/title", "title"]) and (reason in ["duplicate", "already_exists"]) 
      end)
  end

  defp uniquify_title(title) when is_binary(title) do
    suffix = :erlang.unique_integer([:positive]) |> Integer.to_string()
    title <> " (" <> suffix <> ")"
  end

  defp ensure_resume_ready(access_token, resume_id, attempts \\ 12)
       when is_binary(access_token) and is_binary(resume_id) and is_integer(attempts) do
    cond do
      attempts <= 0 -> :ok
      true ->
        case fetch_resume_details(resume_id, access_token) do
          {:ok, _} -> :ok
          _ ->
            Logger.debug("Waiting for resume to become available: id=#{resume_id} attempts_left=#{attempts - 1}")
            Process.sleep(500)
            ensure_resume_ready(access_token, resume_id, attempts - 1)
        end
    end
  end

  defp ensure_existing_resume_completeness(access_token, resume_id, customized_cv)
       when is_binary(access_token) and is_binary(resume_id) and is_map(customized_cv) do
    case fetch_resume_details(resume_id, access_token) do
      {:ok, resume} ->
        missing_education = education_missing?(resume)
        missing_contacts = contacts_missing?(resume)

        updates = %{}
        updates =
          if missing_education do
            Map.put(updates, :education, build_education_sections(Map.get(customized_cv, "education")))
          else
            updates
          end

        updates =
          if missing_contacts do
            case build_contact(customized_cv) do
              {:ok, contacts} -> Map.put(updates, :contact, contacts)
              _ -> updates
            end
          else
            updates
          end

        if map_size(updates) == 0 do
          :ok
        else
          case Req.put("#{@base_url}/resumes/#{resume_id}", headers: hh_headers(access_token), json: updates) do
            {:ok, %{status: status}} when status in [200, 204] -> :ok
            {:ok, %{status: status, body: body}} ->
              Logger.error("HH update resume error status=#{status} body=#{log_term(body)}")
              {:error, {:http_error, status, body}}
            {:error, reason} ->
              Logger.error("HH update resume request failed: #{inspect(reason)}")
              {:error, reason}
          end
        end

      other ->
        Logger.error("Failed to fetch resume before update: #{inspect(other)}")
        :ok
    end
  end

  defp education_missing?(resume) when is_map(resume) do
    lvl = get_in(resume, ["education", "level"]) || get_in(resume, [:education, :level])
    cond do
      is_nil(lvl) -> true
      is_map(lvl) -> (Map.get(lvl, "id") || Map.get(lvl, :id)) in [nil, ""]
      is_binary(lvl) -> String.trim(lvl) == ""
      true -> true
    end
  end

  defp contacts_missing?(resume) when is_map(resume) do
    contacts = Map.get(resume, "contact") || Map.get(resume, :contact)
    not (is_list(contacts) and length(contacts) > 0)
  end

  defp extract_resume_id_from_response(%{body: body} = resp) do
    id =
      body
      |> decode_body()
      |> case do
        %{} = map -> Map.get(map, "id") || Map.get(map, "resume_id")
        _ -> nil
      end

    cond do
      is_binary(id) and id != "" -> id
      true ->
        resp
        |> get_header("location")
        |> case do
          nil -> nil
          loc ->
            parsed = URI.parse(loc)
            path = parsed.path || loc
            path
            |> String.trim()
            |> String.split("/")
            |> Enum.reject(&(&1 == ""))
            |> List.last()
        end
    end
  end

  defp get_header(%{headers: headers}, name) when is_list(headers) and is_binary(name) do
    headers
    |> Enum.find_value(fn {k, v} -> String.downcase(k) == String.downcase(name) && v end)
  end
  defp get_header(_, _), do: nil

  defp resume_payload_summary(%{} = payload) do
    title = Map.get(payload, :title)
    area_id = get_in(payload, [:area, "id"]) || get_in(payload, [:area, :id])
    skills_count =
      case Map.get(payload, :skills) do
        nil -> 0
        s when is_binary(s) -> s |> String.split("\n", trim: true) |> length()
        _ -> 0
      end
    exp_count = case Map.get(payload, :experience) do
      l when is_list(l) -> length(l)
      _ -> 0
    end
    edu_level = get_in(payload, [:education, "level", "id"]) || get_in(payload, [:education, :level, :id])
    contacts_types =
      payload
      |> Map.get(:contact)
      |> case do
        l when is_list(l) -> Enum.map(l, fn c -> get_in(c, ["type", "id"]) || get_in(c, [:type, :id]) end)
        _ -> []
      end
    "title=#{inspect(title)} area=#{inspect(area_id)} skills=#{skills_count} exp=#{exp_count} edu=#{inspect(edu_level)} contacts=#{inspect(contacts_types)}"
  end

  defp log_term(term) do
    s = inspect(term, pretty: false, limit: 50, printable_limit: 500)
    if String.length(s) > 1000, do: String.slice(s, 0, 1000) <> "...(truncated)", else: s
  end
end
