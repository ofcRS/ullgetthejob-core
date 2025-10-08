# HH.ru Job Application Automation - Implementation Plan

## Project Overview
**Goal**: Build a Phoenix/LiveView application that automates job applications on hh.ru using cookies authentication

**Current Status**: Phoenix dashboard set up ✓

---

## Phase 1: Manual Flow Foundation (Week 1-2)

### 1.1 Cookie-Based HH.ru Client
**File**: `lib/job_app/hh_client.ex`

```elixir
defmodule JobApp.HHClient do
  @moduledoc "HTTP client for hh.ru using cookies"
  
  # Store cookies in GenServer state
  def init_session(cookies_string)
  def fetch_jobs(filters)
  def get_job_details(job_id)
  def apply_to_job(job_id, resume_id, cover_letter)
end
```

**Tasks**:
- [ ] Create HTTP client with cookie storage
- [ ] Add rate limiting (1 req/sec)
- [ ] Parse hh.ru job listings
- [ ] Test fetching jobs from your account

### 1.2 CV Upload & Storage
**Files**: 
- `lib/job_app/cv_parser.ex`
- `lib/job_app_web/live/cv_upload_live.ex`

```elixir
defmodule JobApp.CVParser do
  # Parse uploaded CV (PDF/DOCX)
  def parse_file(upload_path)
  
  # Extract structured data
  def extract_sections(%{
    personal_info: %{},
    experience: [],
    skills: [],
    projects: [],
    achievements: []
  })
end
```

**Tasks**:
- [ ] LiveView upload component with Phoenix.LiveView.UploadConfig
- [ ] Store original CV in PostgreSQL (cvs table)
- [ ] Parse PDF with `pdf_text` lib or DOCX with `docx_reader`
- [ ] Extract: name, contact, experience, skills, projects

### 1.3 Job Feed LiveView
**File**: `lib/job_app_web/live/jobs_live.ex`

**UI Components**:
```
┌─────────────────────────────────┐
│ Filters: [City] [Salary] [Remote]│
├─────────────────────────────────┤
│ □ Senior Developer - Company A  │
│   $3000-5000 | Moscow | Remote  │
│   [View] [Select for CV Edit]   │
├─────────────────────────────────┤
│ □ Backend Engineer - Company B  │
│   $2500-4000 | SPb | Office     │
│   [View] [Select for CV Edit]   │
└─────────────────────────────────┘
```

**Tasks**:
- [ ] Fetch jobs via `HHClient`
- [ ] Display with checkboxes for selection
- [ ] Store fetched jobs in DB (`jobs` table with raw JSON)
- [ ] Add pagination

---

## Phase 2: Manual CV Editing (Week 3-4)

### 2.1 AI-Powered CV Restructuring
**File**: `lib/job_app/cv_editor.ex`

```elixir
defmodule JobApp.CVEditor do
  @moduledoc "AI-powered CV customization"
  
  def analyze_job_requirements(job_description)
  def suggest_highlights(cv_data, job_requirements)
  def generate_custom_cv(cv_data, highlights, job_title)
  def generate_cover_letter(cv_data, job_description)
end
```

**Integration Options**:
1. **OpenAI API**: Use GPT-4 for restructuring
2. **Local LLM**: Run llama.cpp via ports
3. **Anthropic Claude API**: Better for long context

**Prompt Template**:
```
Given this CV:
{cv_sections}

And this job description:
{job_description}

Highlight the most relevant:
- 3 key projects
- 5 responsibilities
- 3 achievements

Output as JSON with emphasis scores.
```

**Tasks**:
- [ ] Add `req` for HTTP calls to AI API
- [ ] Create prompt templates
- [ ] Parse AI responses into structured data
- [ ] Store API keys in runtime config

### 2.2 CV Edit Interface
**File**: `lib/job_app_web/live/cv_editor_live.ex`

**UI**:
```
┌────────────────────────────────────────┐
│ Editing CV for: Senior Developer @ Co │
├────────────────────────────────────────┤
│ Original CV    │  AI Suggestions       │
│ ──────────────│───────────────────────│
│ • Project A   │  ✓ Highlight (90%)    │
│ • Project B   │  ✗ Less relevant (30%)│
│ • Project C   │  ✓ Emphasize (85%)    │
│               │                        │
│ [Apply Suggestions] [Manual Edit]     │
└────────────────────────────────────────┘
```

**Tasks**:
- [ ] Side-by-side comparison view
- [ ] Toggle suggestions on/off
- [ ] Live preview of edited CV
- [ ] Save custom CV version per job

### 2.3 Application Preview & Confirmation
**File**: `lib/job_app_web/live/application_preview_live.ex`

**Flow**:
1. Show customized CV preview
2. Display generated cover letter
3. Show job details again
4. **[Confirm Application]** button

**Tasks**:
- [ ] Render CV as HTML preview
- [ ] Editable cover letter textarea
- [ ] Confirmation modal with final check
- [ ] Store application attempt in DB

---

## Phase 3: Manual Application Flow (Week 5)

### 3.1 Application Submission
**File**: `lib/job_app/applicator.ex`

```elixir
defmodule JobApp.Applicator do
  def submit_application(%{
    job_id: job_id,
    custom_cv_path: path,
    cover_letter: text,
    cookies: cookies
  }) do
    # 1. Upload CV to hh.ru
    # 2. Fill application form
    # 3. Submit with cover letter
    # 4. Handle confirmation
  end
end
```

**Cookie-Based Approach**:
- Use stored session cookies
- Make POST requests mimicking browser
- Handle CSRF tokens from hh.ru
- Monitor for session expiration

**Tasks**:
- [ ] Reverse engineer hh.ru application form
- [ ] Build form submission with Req
- [ ] Handle file uploads
- [ ] Parse success/error responses
- [ ] Log all attempts with status

### 3.2 Application Tracking
**Database Schema**:
```sql
CREATE TABLE applications (
  id UUID PRIMARY KEY,
  job_id BIGINT,
  custom_cv_id UUID,
  cover_letter TEXT,
  status VARCHAR(50), -- pending, submitted, error
  submitted_at TIMESTAMP,
  response TEXT
);
```

**Tasks**:
- [ ] Create Ecto schema
- [ ] Track application status
- [ ] Display application history in dashboard
- [ ] Retry failed applications

---

## Phase 4: Automation (Week 6-7)

### 4.1 Automated Pipeline GenServer
**File**: `lib/job_app/automation_engine.ex`

```elixir
defmodule JobApp.AutomationEngine do
  use GenServer
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  # Periodic job: fetch → analyze → edit → apply
  def handle_info(:process_batch, state) do
    jobs = fetch_new_jobs()
    
    Enum.each(jobs, fn job ->
      custom_cv = generate_custom_cv(job)
      submit_application(job, custom_cv)
      Process.sleep(5000) # Rate limit
    end)
    
    schedule_next_batch()
    {:noreply, state}
  end
end
```

**Tasks**:
- [ ] Create GenServer for automation
- [ ] Add configurable filters (salary, location, keywords)
- [ ] Schedule periodic runs (every 6 hours)
- [ ] Respect hh.ru rate limits
- [ ] Add kill switch for emergencies

### 4.2 Smart Filtering
**File**: `lib/job_app/job_matcher.ex`

```elixir
defmodule JobApp.JobMatcher do
  # Score jobs based on user preferences
  def score_job(job, user_cv, preferences) do
    %{
      salary_match: 0.8,
      skills_match: 0.9,
      location_match: 1.0,
      total_score: 0.9
    }
  end
  
  # Only apply to jobs above threshold
  def should_apply?(score), do: score.total_score > 0.7
end
```

**Tasks**:
- [ ] Keyword matching for required skills
- [ ] Salary range filtering
- [ ] Location preferences
- [ ] Skip already applied jobs
- [ ] Blacklist companies

### 4.3 Monitoring Dashboard
**File**: `lib/job_app_web/live/automation_dashboard_live.ex`

**Metrics to Display**:
- Jobs fetched today
- Applications submitted (auto vs manual)
- Success rate
- Average response time
- Next scheduled run

**Tasks**:
- [ ] Real-time metrics with LiveView
- [ ] Charts with Phoenix.LiveDashboard or custom
- [ ] Application log viewer
- [ ] Pause/resume automation controls

---

## Phase 5: Testing & Safeguards (Week 8)

### 5.1 Testing Strategy
```elixir
# test/job_app/hh_client_test.exs
defmodule JobApp.HHClientTest do
  use ExUnit.Case
  
  # Mock hh.ru responses
  test "fetches jobs with filters" do
    # Test with recorded HTTP fixtures
  end
  
  test "handles rate limiting" do
    # Ensure 1 req/sec limit
  end
end
```

**Tasks**:
- [ ] Unit tests for all modules
- [ ] Integration tests with VCR-like HTTP mocking
- [ ] Test CV parsing with sample files
- [ ] Test AI prompts with mock responses

### 5.2 Safety Features
- [ ] Daily application limit (e.g., max 10/day)
- [ ] Duplicate detection (don't apply twice)
- [ ] Session validation (re-login if cookies expire)
- [ ] Email notifications on errors
- [ ] Dry-run mode (preview without submitting)

---

## Tech Stack Summary

### Core
- **Elixir 1.18** + **Phoenix 1.7**
- **Phoenix LiveView** for reactive UI
- **PostgreSQL** for data storage
- **Ecto** for database queries

### Libraries
```elixir
# mix.exs
{:phoenix_live_view, "~> 1.0"},
{:req, "~> 0.5"},           # HTTP client
{:floki, "~> 0.36"},        # HTML parsing
{:pdf_text, "~> 0.1"},      # PDF parsing (or elixir-pdf-generator)
{:jason, "~> 1.4"},         # JSON
{:oban, "~> 2.18"},         # Background jobs (for automation)
{:telemetry_metrics, "~> 1.0"} # Monitoring
```

### AI Integration (Choose One)
1. **OpenAI**: `{:openai, "~> 0.6"}`
2. **Anthropic**: `{:anthropic, "~> 0.2"}` or direct Req calls
3. **Local LLM**: Port to llama.cpp binary

---

## File Structure

```
lib/
├── job_app/
│   ├── application.ex          # App supervisor
│   ├── hh_client.ex            # HH.ru API wrapper
│   ├── cv_parser.ex            # CV parsing
│   ├── cv_editor.ex            # AI-powered editing
│   ├── job_matcher.ex          # Smart filtering
│   ├── applicator.ex           # Submit applications
│   ├── automation_engine.ex    # GenServer for automation
│   └── repo.ex                 # Ecto repo
├── job_app_web/
│   ├── live/
│   │   ├── cv_upload_live.ex
│   │   ├── jobs_live.ex
│   │   ├── cv_editor_live.ex
│   │   ├── application_preview_live.ex
│   │   └── automation_dashboard_live.ex
│   └── router.ex
priv/
└── repo/migrations/
    ├── 001_create_cvs.exs
    ├── 002_create_jobs.exs
    └── 003_create_applications.exs
```

---

## Development Roadmap

### Sprint 1 (Weeks 1-2): Foundation
- Set up cookie-based HH client
- Build CV upload & parsing
- Create job listing view

### Sprint 2 (Weeks 3-4): Manual Editing
- Integrate AI for CV suggestions
- Build side-by-side editor
- Generate cover letters

### Sprint 3 (Week 5): Manual Application
- Implement form submission
- Add confirmation flow
- Track application status

### Sprint 4 (Weeks 6-7): Automation
- Build automation GenServer
- Add smart filtering
- Create monitoring dashboard

### Sprint 5 (Week 8): Polish
- Add comprehensive tests
- Implement safety limits
- Deploy to production

---

## Environment Configuration

```elixir
# config/runtime.exs
config :job_app, JobApp.HHClient,
  cookies: System.get_env("HH_COOKIES"),
  rate_limit: 1_000  # ms between requests

config :job_app, JobApp.AIService,
  provider: :openai,  # or :anthropic, :local
  api_key: System.get_env("OPENAI_API_KEY"),
  model: "gpt-4"

config :job_app, JobApp.Automation,
  enabled: System.get_env("AUTO_APPLY") == "true",
  max_daily_applications: 10,
  schedule: "0 */6 * * *"  # Every 6 hours
```

---

## Cursor Agent Instructions

When implementing:
1. **Start with Phase 1** - Don't jump ahead
2. **Test each module independently** before integration
3. **Use LiveView for all UI** - avoid JS complexity
4. **Store everything in DB** - jobs, CVs, applications
5. **Add logging everywhere** - use Logger.info
6. **Handle errors gracefully** - with {:ok, _} | {:error, _}
7. **Rate limit aggressively** - don't get banned
8. **Make it visible** - LiveView should show real-time progress

### First Commands:
```bash
# Add dependencies
mix deps.get

# Create database tables
mix ecto.create && mix ecto.migrate

# Start dev server
mix phx.server
```

### Testing with Real Data:
1. Get your hh.ru cookies from browser DevTools
2. Store in .env: `export HH_COOKIES="your_cookies_here"`
3. Test fetching jobs manually first
4. Try submitting one test application
5. Only then enable automation

---

## Future Enhancements (Post-MVP)

- [ ] Multi-platform support (LinkedIn, Indeed)
- [ ] A/B testing different CV versions
- [ ] Response tracking (when employers reply)
- [ ] Interview scheduling automation
- [ ] Chrome extension for cookie extraction
- [ ] Telegram bot for notifications
- [ ] Analytics dashboard (conversion rates)

---

## Security Considerations

⚠️ **Critical**:
- Never commit cookies to Git
- Use `.env` files (add to `.gitignore`)
- Encrypt stored cookies in DB
- Rotate cookies regularly
- Monitor for unusual activity
- Add 2FA to your app

---

**Ready to start? Begin with Phase 1.1 - the HH Client!**