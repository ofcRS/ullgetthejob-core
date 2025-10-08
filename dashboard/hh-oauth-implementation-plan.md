# HH.ru OAuth API Implementation Plan

## Goal
Get the application working end-to-end with real HH.ru API:
1. Upload CV → 2. See vacancies → 3. Select one → 4. Create customized resume → 5. Apply

---

## What's Already Working ✓

- ✓ CV upload and parsing
- ✓ Job fetching from HH.ru public API
- ✓ Job selection UI
- ✓ AI-powered CV customization
- ✓ Cover letter generation
- ✓ Application preview UI

## What Needs Implementation

- ❌ OAuth token authentication
- ❌ Resume upload to HH.ru
- ❌ Real application submission
- ❌ HH.ru API error handling

---

## Phase 1: OAuth Token Setup (30 min)

### 1.1 Environment Configuration

**Update:** `config/runtime.exs`

```elixir
# HH.ru OAuth Configuration
config :dashboard, Dashboard.HH.Client,
  access_token: System.get_env("HH_ACCESS_TOKEN"),
  # Legacy cookie support (remove later)
  cookies_file: System.get_env("HH_COOKIES_FILE")
```

**Create:** `.env` file (add to `.gitignore`)

```bash
# HH.ru OAuth Token
HH_ACCESS_TOKEN=your_token_here

# OpenRouter for AI
OPENROUTER_API_KEY=your_key_here
```

### 1.2 Update HH Client

**File:** `lib/dashboard/hh/client.ex`

**Changes:**
1. Add token-based authentication support
2. Keep cookie support as fallback
3. Add helper methods for common API calls

**Key additions:**

```elixir
defmodule Dashboard.HH.Client do
  # ... existing code ...

  # Add to State struct
  defmodule State do
    defstruct [
      :cookies,
      :cookies_file,
      :access_token,  # NEW
      :last_loaded,
      session_valid: true
    ]
  end

  # Update init to support tokens
  @impl true
  def init(opts) do
    access_token = Keyword.get(opts, :access_token) || 
                   Application.get_env(:dashboard, __MODULE__)[:access_token]

    state = if access_token do
      %State{
        access_token: access_token,
        session_valid: true
      }
    else
      # Fallback to cookies (existing code)
      cookies_file = Keyword.get(opts, :cookies_file, "hh.ru_cookies.txt")
      case load_cookies(cookies_file) do
        {:ok, cookies} ->
          %State{
            cookies: cookies,
            cookies_file: cookies_file,
            last_loaded: DateTime.utc_now()
          }
        {:error, reason} ->
          Logger.error("No auth available: #{inspect(reason)}")
          {:stop, {:error, :no_auth}}
      end
    end

    {:ok, state}
  end

  # Update build_headers to use token if available
  defp build_headers(%State{access_token: token} = _state, opts) when not is_nil(token) do
    base_headers = [
      {"Authorization", "Bearer #{token}"},
      {"User-Agent", "YourApp/1.0 (your@email.com)"},  # HH.ru requires this
      {"Accept", "application/json"},
      {"Content-Type", "application/json"}
    ]
    
    custom_headers = Keyword.get(opts, :headers, [])
    base_headers ++ custom_headers
  end

  # Existing cookie-based headers
  defp build_headers(%State{cookies: cookies} = _state, opts) when not is_nil(cookies) do
    # ... existing cookie code ...
  end
end
```

---

## Phase 2: Resume Management API (1 hour)

### 2.1 Create Resume Manager Module

**Create:** `lib/dashboard/hh/resume_manager.ex`

This module handles HH.ru resume operations.

```elixir
defmodule Dashboard.HH.ResumeManager do
  @moduledoc """
  Manages resumes on HH.ru via API.
  
  API Docs: https://github.com/hhru/api/blob/master/docs/resumes.md
  """
  require Logger
  
  alias Dashboard.HH.Client

  @doc """
  Lists all resumes for the authenticated user.
  
  Returns: {:ok, [%{id: "...", title: "...", ...}]} or {:error, reason}
  """
  def list_resumes do
    case Client.get("/resumes/mine") do
      {:ok, %{"items" => resumes}} ->
        {:ok, resumes}
      
      {:ok, response} ->
        Logger.warning("Unexpected response: #{inspect(response)}")
        {:error, :unexpected_response}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets full resume details by ID.
  """
  def get_resume(resume_id) do
    Client.get("/resumes/#{resume_id}")
  end

  @doc """
  Creates a new resume on HH.ru from our CV data.
  
  Resume structure: https://github.com/hhru/api/blob/master/docs/resumes.md#resume-fields
  """
  def create_resume(cv_data, opts \\ []) do
    resume_data = build_resume_json(cv_data, opts)
    
    case Client.post("/resumes", resume_data) do
      {:ok, %{"id" => resume_id} = response} ->
        Logger.info("Created resume on HH.ru: #{resume_id}")
        {:ok, response}
      
      {:ok, response} ->
        Logger.error("Failed to create resume: #{inspect(response)}")
        {:error, {:creation_failed, response}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates an existing resume.
  """
  def update_resume(resume_id, cv_data, opts \\ []) do
    resume_data = build_resume_json(cv_data, opts)
    
    Client.put("/resumes/#{resume_id}", resume_data)
  end

  @doc """
  Publishes a resume (makes it visible to employers).
  """
  def publish_resume(resume_id) do
    Client.post("/resumes/#{resume_id}/publish", %{})
  end

  # Private functions

  defp build_resume_json(cv_data, opts) do
    personal_info = Map.get(cv_data, "personal_info", %{})
    
    %{
      # Basic info
      last_name: extract_last_name(personal_info),
      first_name: extract_first_name(personal_info),
      middle_name: nil,
      
      # Title
      title: Keyword.get(opts, :title) || Map.get(personal_info, "title", "Resume"),
      
      # Contact info
      contact: build_contact(personal_info),
      
      # Experience
      experience: build_experience(cv_data),
      
      # Skills
      skill_set: build_skills(cv_data),
      
      # Education
      education: build_education(cv_data),
      
      # Additional
      language: [%{id: "eng", level: %{id: "l1"}}],  # English - basic
    }
  end

  defp extract_first_name(personal_info) do
    case Map.get(personal_info, "name", "") |> String.split(" ") do
      [first | _] -> first
      _ -> "User"
    end
  end

  defp extract_last_name(personal_info) do
    case Map.get(personal_info, "name", "") |> String.split(" ") do
      [_, last | _] -> last
      _ -> ""
    end
  end

  defp build_contact(personal_info) do
    [
      %{
        type: %{id: "email"},
        value: Map.get(personal_info, "email", "")
      },
      %{
        type: %{id: "cell"},
        value: Map.get(personal_info, "phone", "")
      }
    ]
    |> Enum.reject(fn contact -> contact.value == "" end)
  end

  defp build_experience(cv_data) do
    cv_data
    |> Map.get("experience", [])
    |> Enum.map(fn exp ->
      %{
        company: Map.get(exp, "company", ""),
        position: Map.get(exp, "title", ""),
        description: Map.get(exp, "description", ""),
        start: parse_date_for_hh(Map.get(exp, "period", "")),
        end: nil  # Current position
      }
    end)
  end

  defp build_skills(cv_data) do
    skills = Map.get(cv_data, "skills", [])
    
    if Enum.empty?(skills) do
      []
    else
      [Enum.join(skills, ", ")]
    end
  end

  defp build_education(cv_data) do
    cv_data
    |> Map.get("education", [])
    |> Enum.map(fn edu ->
      %{
        name: Map.get(edu, "institution", ""),
        organization: Map.get(edu, "institution", ""),
        result: Map.get(edu, "degree", ""),
        year: parse_year(Map.get(edu, "year", ""))
      }
    end)
  end

  defp parse_date_for_hh(period_string) do
    # Extract year from strings like "2020 - 2023" or "Jan 2020 - Present"
    case Regex.run(~r/\d{4}/, period_string) do
      [year] -> String.to_integer(year)
      _ -> DateTime.utc_now().year
    end
  end

  defp parse_year(year_string) do
    case Integer.parse(to_string(year_string)) do
      {year, _} when year > 1950 and year < 2030 -> year
      _ -> DateTime.utc_now().year
    end
  end
end
```

### 2.2 Update Application Schema

**File:** `lib/dashboard/applications/application.ex`

Add field to track HH.ru resume ID:

```elixir
schema "applications" do
  # ... existing fields ...
  field :hh_resume_id, :string  # NEW: ID of resume on HH.ru
  field :hh_negotiation_id, :string  # NEW: ID of application/negotiation on HH.ru
  # ...
end

def changeset(application, attrs) do
  application
  |> cast(attrs, [
    :job_id,
    :custom_cv_id,
    :job_external_id,
    :cover_letter,
    :status,
    :submitted_at,
    :response_data,
    :error_message,
    :hh_resume_id,  # NEW
    :hh_negotiation_id  # NEW
  ])
  # ...
end
```

**Create migration:**

```bash
mix ecto.gen.migration add_hh_ids_to_applications
```

**File:** `priv/repo/migrations/*_add_hh_ids_to_applications.exs`

```elixir
defmodule Dashboard.Repo.Migrations.AddHhIdsToApplications do
  use Ecto.Migration

  def change do
    alter table(:applications) do
      add :hh_resume_id, :string
      add :hh_negotiation_id, :string
    end

    create index(:applications, [:hh_resume_id])
    create index(:applications, [:hh_negotiation_id])
  end
end
```

---

## Phase 3: Real Application Submission (1 hour)

### 3.1 Update Applicator

**File:** `lib/dashboard/applications/applicator.ex`

Replace stub implementation with real API calls.

```elixir
defmodule Dashboard.Applications.Applicator do
  @moduledoc """
  Submits job applications to HH.ru using OAuth API.
  """
  require Logger

  alias Dashboard.HH.Client
  alias Dashboard.HH.ResumeManager
  alias Dashboard.Applications
  alias Dashboard.Applications.Application
  alias Dashboard.CVs

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
    case Dashboard.CVEditor.get_custom_cv(custom_cv_id) do
      {:ok, custom_cv} ->
        # Preload CV if needed
        custom_cv = Dashboard.Repo.preload(custom_cv, :cv)
        {:ok, custom_cv}
      
      error -> error
    end
  end

  @doc """
  Gets existing HH.ru resume or creates a new one.
  """
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

    case Dashboard.Repo.one(query) do
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

  @doc """
  Creates a negotiation (application) on HH.ru.
  
  API: POST /negotiations
  Docs: https://github.com/hhru/api/blob/master/docs/negotiations.md
  """
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

  @doc """
  Adds cover letter as a message to the negotiation.
  """
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
    config = Application.get_env(:dashboard, Dashboard.Applications, [])
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
```

### 3.2 Add PUT support to HH Client

**File:** `lib/dashboard/hh/client.ex`

Add PUT method (needed for resume updates):

```elixir
@doc """
Makes an authenticated PUT request to HH.ru
"""
def put(path, body, opts \\ []) do
  GenServer.call(__MODULE__, {:put, path, body, opts}, 30_000)
end

@impl true
def handle_call({:put, path, body, opts}, _from, state) do
  url = build_url(path, opts)
  headers = build_headers(state, opts)

  Logger.debug("PUT #{url}")

  case Req.put(url, headers: headers, json: body) do
    {:ok, %{status: status, body: response_body}} when status in 200..299 ->
      {:reply, {:ok, response_body}, state}

    {:ok, %{status: 401}} ->
      Logger.warning("Session expired (401)")
      new_state = %{state | session_valid: false}
      {:reply, {:error, :session_expired}, new_state}

    {:ok, %{status: status}} ->
      {:reply, {:error, {:unexpected_status, status}}, state}

    {:error, reason} ->
      {:reply, {:error, reason}, state}
  end
end
```

---

## Phase 4: Update Application Supervisor (5 min)

**File:** `lib/dashboard/application.ex`

Update the HH.Client initialization to use token:

```elixir
def start(_type, _args) do
  children = [
    # ... existing children ...
    
    # HH.ru client with OAuth token support
    {Dashboard.HH.Client, 
      access_token: Application.get_env(:dashboard, Dashboard.HH.Client)[:access_token],
      cookies_file: Application.get_env(:dashboard, Dashboard.HH.Client)[:cookies_file]
    },
    
    # ... rest ...
  ]
  
  # ...
end
```

---

## Phase 5: Testing & Debugging (30 min)

### 5.1 Test Resume Creation

Create a test script: `lib/mix/tasks/test_hh_api.ex`

```elixir
defmodule Mix.Tasks.TestHhApi do
  use Mix.Task
  require Logger

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
    case Dashboard.CVs.get_active_cv() do
      nil ->
        Logger.error("✗ No CV found. Please upload one first.")
      
      cv ->
        Logger.info("✓ Found CV: #{cv.name}")
        
        # Test 3: Create resume
        Logger.info("3. Creating test resume on HH.ru...")
        case Dashboard.HH.ResumeManager.create_resume(cv.parsed_data, title: "Test Resume") do
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
    end

    Logger.info("Test complete!")
  end
end
```

**Run tests:**

```bash
# Set your token
export HH_ACCESS_TOKEN="your_token_here"

# Run test
mix test_hh_api
```

### 5.2 Debug Checklist

If things don't work, check:

1. **Token Valid?**
   ```bash
   curl -H "Authorization: Bearer YOUR_TOKEN" https://api.hh.ru/me
   ```

2. **Token Permissions?**
   - Need: `resumes` and `negotiations` scopes

3. **Check Logs:**
   ```bash
   tail -f log/dev.log
   ```

4. **Common Errors:**
   - `403 Forbidden` → Token lacks permissions
   - `400 Bad Request` → Check JSON structure
   - `404 Not Found` → Wrong vacancy/resume ID

---

## Phase 6: UI Updates (Optional)

### 6.1 Show HH.ru Resume Link

**File:** `lib/dashboard_web/live/application_show_live.ex`

Add link to HH.ru application:

```elixir
<%= if @application.hh_negotiation_id do %>
  <div class="mt-4 p-4 bg-blue-50 border border-blue-200 rounded-lg">
    <p class="text-sm text-blue-900 mb-2">Application on HH.ru:</p>
    <a 
      href={"https://hh.ru/applicant/negotiations/#{@application.hh_negotiation_id}"}
      target="_blank"
      class="text-blue-600 hover:underline font-medium"
    >
      View on HH.ru →
    </a>
  </div>
<% end %>
```

---

## Quick Start Guide

### 1. Get HH.ru OAuth Token

**Option A: Use their OAuth flow**
1. Register app: https://dev.hh.ru/
2. Get Client ID & Secret
3. Implement OAuth callback (or use their playground)

**Option B: Use Personal Access Token (easier for testing)**
1. Go to https://dev.hh.ru/
2. Create personal access token
3. Copy token

### 2. Configure

```bash
# .env
HH_ACCESS_TOKEN="your_token_here"
OPENROUTER_API_KEY="your_ai_key"
```

### 3. Run Migration

```bash
mix ecto.migrate
```

### 4. Test

```bash
# Test API connection
mix test_hh_api

# Start server
mix phx.server
```

### 5. Use Application

1. **Upload CV:** `/cvs/upload`
2. **Browse Jobs:** `/jobs` → Click "Fetch Now"
3. **Select Job:** Check the job you want
4. **Customize:** Click "Customize CV & Apply"
5. **Apply:** Review and click "Submit Application"

---

## Implementation Order

Do it in this exact order:

1. **Phase 1** (30 min) - OAuth setup and config
2. **Phase 4** (5 min) - Update supervisor
3. **Phase 2** (1 hour) - Resume management
4. **Phase 3** (1 hour) - Application submission
5. **Phase 5** (30 min) - Testing
6. **Phase 6** (optional) - UI polish

**Total Time: ~3 hours**

---

## Troubleshooting

### "No auth available" error
- Set `HH_ACCESS_TOKEN` environment variable
- Restart server after setting

### "Token expired"
- Get new token from HH.ru
- Update `.env` file

### "Failed to create resume"
- Check CV data has required fields (name, email)
- Look at error details in logs
- Try with minimal resume first

### "Negotiation failed"
- Check if resume is published
- Verify vacancy_id is correct
- Check token has `negotiations` permission

---

## API Documentation

**Official HH.ru API:**
- Main: https://github.com/hhru/api
- Resumes: https://github.com/hhru/api/blob/master/docs/resumes.md
- Applications: https://github.com/hhru/api/blob/master/docs/negotiations.md
- OAuth: https://github.com/hhru/api/blob/master/docs/authorization.md

---

## What Gets Removed Later

Once OAuth works, you can remove:
- Cookie-based authentication
- `HH.CookieParser` module
- `hh.ru_cookies.txt` file
- Cookie-related code in `HH.Client`

But keep it for now as fallback during testing.

---

## Success Criteria

You know it works when:
- ✓ You can upload a CV
- ✓ Jobs appear when you click "Fetch Now"
- ✓ You can select a job and customize CV
- ✓ "Submit Application" creates real application on HH.ru
- ✓ You can see the application in your HH.ru account
- ✓ Application appears in `/applications` with "submitted" status

---

## Next Steps (After It Works)

1. **Error Recovery:** Handle API failures gracefully
2. **Batch Applications:** Apply to multiple jobs at once
3. **Application Tracking:** Sync status from HH.ru
4. **Resume Reuse:** Don't create duplicate resumes
5. **OAuth Flow:** Implement proper OAuth for production

But first: **Make it work!** 🚀