# 🔥 UllGetTheJob Core

> **Phoenix-powered orchestrator for intelligent job applications**  
> The single source of truth for database schema, HH.ru integration, and real-time job orchestration

[![Elixir](https://img.shields.io/badge/Elixir-1.15+-4B275F?logo=elixir)](https://elixir-lang.org/)
[![Phoenix](https://img.shields.io/badge/Phoenix-1.8-orange?logo=phoenix-framework)](https://www.phoenixframework.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14+-blue?logo=postgresql)](https://www.postgresql.org/)

---

## 📖 Overview

**UllGetTheJob Core** is the backend orchestrator that powers the entire job application automation system. Built with Phoenix and Elixir, it provides:

- 🗄️ **Database Schema Management** - Ecto migrations and PostgreSQL integration
- 🔐 **HH.ru OAuth Flow** - Complete authentication with token management
- 🔄 **Job Fetching Orchestrator** - Periodic job search with rate limiting
- 📡 **WebSocket Broadcasting** - Real-time job updates to connected clients
- 🎯 **Application Submission** - HH.ru API integration for resume operations
- ⚡ **Rate Limiting** - Token bucket algorithm for API quota management

---

## 🏗️ Architecture
```
┌─────────────────────────────────────────────────────────┐
│                    Phoenix Core                          │
├─────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │  HH.ru API   │  │ Rate Limiter │  │ Job Fetcher  │ │
│  │   Client     │  │  (GenServer) │  │(Orchestrator)│ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│         │                  │                  │         │
│         └──────────────────┴──────────────────┘         │
│                            │                            │
│                   ┌────────▼────────┐                   │
│                   │  Ecto + Postgres │                  │
│                   └─────────────────┘                   │
└─────────────────────────────────────────────────────────┘
                            │
                ┌───────────┴───────────┐
                │                       │
         REST API (Node BFF)    WebSocket (Broadcast)
```

---

## 🚀 Quick Start

### Prerequisites

- **Elixir** ~> 1.15
- **Erlang** ~> 26
- **PostgreSQL** 14+
- **Mix** (comes with Elixir)

### Installation
```bash
# Clone the repository
git clone <repo-url>
cd ullgetthejob-core

# Install dependencies
mix deps.get

# Setup database (create, migrate, seed)
mix setup

# Start Phoenix server
mix phx.server
```

Server runs at **http://localhost:4000** 🎉

### Development with IEx
```bash
# Start with interactive shell
iex -S mix phx.server

# Useful IEx commands:
iex> Core.HH.Client.fetch_vacancies(%{text: "Elixir"})
iex> Core.Jobs.Orchestrator.fetch_jobs_now("user_id")
iex> Core.RateLimiter.get_status("user_id")
```

---

## 🔧 Configuration

### Environment Variables

Create a `.env` file or set these in your environment:
```bash
# Database
DATABASE_URL="postgresql://postgres:postgres@localhost:5432/ullget_dev"

# HH.ru API
HH_ACCESS_TOKEN="your_hh_api_token"
HH_CLIENT_ID="your_oauth_client_id"
HH_CLIENT_SECRET="your_oauth_client_secret"
HH_REDIRECT_URI="http://localhost:5173/auth/callback"

# Security
ORCHESTRATOR_SECRET="shared_secret_between_core_and_api"
SECRET_KEY_BASE="generate_with_mix_phx_gen_secret"

# External Services
API_BASE_URL="http://localhost:3000"  # Node BFF URL
```

### Generate Secrets
```bash
# Generate SECRET_KEY_BASE
mix phx.gen.secret

# Generate ORCHESTRATOR_SECRET
mix phx.gen.secret 32
```

---

## 📡 API Endpoints

### Public API (for Node BFF)

#### Job Search
```http
POST /api/jobs/search
Content-Type: application/json
X-Core-Secret: <orchestrator_secret>

{
  "text": "JavaScript Developer",
  "area": "1",
  "experience": "between1And3",
  "employment": "full",
  "schedule": "remote"
}
```

#### Application Submission
```http
POST /api/applications/submit
Content-Type: application/json
X-Core-Secret: <orchestrator_secret>

{
  "user_id": "uuid",
  "job_external_id": "hh_vacancy_id",
  "customized_cv": { /* parsed CV object */ },
  "cover_letter": "Dear Hiring Manager..."
}
```

### OAuth Flow (HH.ru)

#### 1. Initiate OAuth
```http
GET /auth/hh/redirect

Response:
{
  "url": "https://hh.ru/oauth/authorize?...",
  "state": "random_state_token"
}
```

#### 2. Handle Callback
```http
GET /auth/hh/callback?code=AUTH_CODE

Response:
{
  "success": true,
  "tokens": {
    "access_token": "...",
    "refresh_token": "...",
    "expires_at": "2025-10-15T12:00:00Z"
  }
}
```

#### 3. Refresh Token
```http
POST /auth/hh/refresh
Content-Type: application/json

{
  "refresh_token": "existing_refresh_token"
}
```

### HH.ru Resume Operations
```http
# List user's resumes
GET /api/hh/resumes

# Get resume details
GET /api/hh/resumes/:resume_id
```

### Health Check
```http
GET /api/v1/system/health

Response:
{
  "status": "ok",
  "db": "up"
}
```

---

## 💾 Database Schema

### Core Tables
```sql
-- HH.ru OAuth tokens (MVP: plaintext, add encryption later)
hh_tokens (
  id uuid PRIMARY KEY,
  user_id uuid,
  access_token text NOT NULL,
  refresh_token text,
  expires_at timestamp NOT NULL
)

-- Jobs fetched from HH.ru
jobs (
  id uuid PRIMARY KEY,
  external_id varchar UNIQUE NOT NULL,
  title varchar NOT NULL,
  company varchar,
  salary varchar,
  area varchar,
  url text,
  description text,
  hh_vacancy_id varchar,
  has_test boolean DEFAULT false,
  skills varchar[]
)

-- Parsed CVs (managed by API service)
parsed_cvs (
  id uuid PRIMARY KEY,
  user_id uuid,
  first_name varchar,
  last_name varchar,
  email varchar,
  phone varchar,
  title varchar,
  summary text,
  experience text,
  education text,
  skills varchar[],
  ...
)
```

### Migrations
```bash
# Create new migration
mix ecto.gen.migration add_new_table

# Run migrations
mix ecto.migrate

# Rollback last migration
mix ecto.rollback

# Reset database
mix ecto.reset
```

---

## 🔄 Background Jobs

### Job Orchestrator

Automatically fetches jobs from HH.ru based on scheduled searches:
```elixir
# Schedule periodic job fetching for a user
Core.Jobs.Orchestrator.schedule_job_fetch(
  "user_id",
  %{text: "Elixir Developer", area: "1"},
  1_800_000  # 30 minutes
)

# Manually trigger fetch
Core.Jobs.Orchestrator.fetch_jobs_now("user_id")

# View active schedules
Core.Jobs.Orchestrator.get_schedules()
```

### Rate Limiter

Token bucket implementation for HH.ru API compliance:
```elixir
# Check if action is allowed
Core.RateLimiter.check_rate_limit("user_id", :application)
# => {:ok, 19} | {:error, :rate_limited, next_refill_time}

# Get current status
Core.RateLimiter.get_status("user_id")
# => %{tokens: 20, capacity: 20, refill_rate: 8, last_refill: ...}

# Reset limit (admin only)
Core.RateLimiter.reset_limit("user_id")
```

**Configuration:**
- Capacity: 20 tokens
- Refill rate: 8 tokens/hour
- HH.ru limit: ~200 applications/day

---

## 📊 Monitoring

### LiveDashboard

Access Phoenix LiveDashboard (development only):
```
http://localhost:4000/dev/dashboard
```

Features:
- Real-time metrics
- Process inspection
- Ecto query analysis
- Request logging

### Telemetry Metrics

Core emits telemetry events for:
- `phoenix.router_dispatch.*` - Request handling
- `core.repo.query.*` - Database operations
- Custom job orchestrator events

---

## 🧪 Testing
```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test file
mix test test/core/hh/client_test.exs

# Run tests matching pattern
mix test --only hh_api
```

---

## 🔒 Security Considerations

### Current Implementation (MVP)

⚠️ **Not production-ready:**
- OAuth tokens stored as plaintext
- No user authentication/authorization
- Rate limiting per `user_id` without validation

### Production Checklist

- [ ] Encrypt sensitive fields (tokens, secrets)
- [ ] Implement proper authentication (Guardian, Pow)
- [ ] Add request signing for API endpoints
- [ ] Enable HTTPS/TLS
- [ ] Implement CSRF protection
- [ ] Add audit logging
- [ ] Set up monitoring/alerting

---

## 📚 Project Structure
```
lib/
├── core/
│   ├── application.ex          # OTP Application
│   ├── repo.ex                  # Ecto Repository
│   ├── hh/
│   │   ├── client.ex           # HH.ru API client
│   │   ├── oauth.ex            # Token management
│   │   └── token.ex            # Token schema
│   ├── jobs/
│   │   └── orchestrator.ex     # Job fetching orchestrator
│   ├── rate_limiter.ex         # Rate limiting GenServer
│   └── broadcaster.ex          # WebSocket broadcast helper
├── core_web/
│   ├── endpoint.ex             # Phoenix Endpoint
│   ├── router.ex               # Route definitions
│   ├── controllers/
│   │   ├── auth_controller.ex  # OAuth endpoints
│   │   ├── hh_controller.ex    # Resume operations
│   │   └── api/
│   │       ├── job_controller.ex
│   │       └── application_controller.ex
│   └── telemetry.ex            # Metrics
priv/
└── repo/
    └── migrations/             # Database migrations
```

---

## 🤝 Integration with Other Services

### Node BFF (API Service)

Core acts as the data layer and HH.ru proxy for the Node BFF:
```
Node BFF → [X-Core-Secret] → Core → HH.ru API
                              ↓
                         PostgreSQL
```

### Frontend (SvelteKit)

Frontend connects to Node BFF, which proxies to Core:
```
Frontend → Node BFF → Core → HH.ru
                  ↓      ↓
              WebSocket  DB
```

---

## 📖 Additional Resources

- [Phoenix Framework Docs](https://hexdocs.pm/phoenix)
- [Ecto Documentation](https://hexdocs.pm/ecto)
- [HH.ru API Documentation](https://github.com/hhru/api)
- [Elixir Getting Started](https://elixir-lang.org/getting-started/introduction.html)

---

## 📄 License

MIT License © 2025 Aleksandr Sakhatskiy

---

<div align="center">
  <strong>Built with 💜 and Elixir</strong>
  <br>
  <sub>Because job hunting should be automated</sub>
</div>