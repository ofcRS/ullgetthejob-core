# 🎯 UllGetTheJob Core

> **Phoenix-powered orchestrator and HH.ru integration backend** 🔥  
> Orchestrator that owns DB schema and exposes APIs for Node.js BFF

---

## ✨ What's This?

**UllGetTheJob Core** is the orchestrator backend and single source of truth, handling:

- 🚀 **Real-time updates** with Phoenix LiveView
- 📊 **Job application tracking** and management
- 🔐 **Authentication & authorization** 
- 💾 **PostgreSQL database** integration with Ecto (migrations owner)
- 🎨 **Server-rendered UI** with LiveView components
- 🧩 **HH.ru OAuth** and resume operations (via tokens)

---

## 🛠️ Tech Stack

- **Phoenix 1.8** - Modern web framework
- **Elixir ~> 1.15** - Functional, concurrent language
- **Ecto + PostgreSQL** - Database layer
- **Phoenix LiveView** - Real-time server-rendered UI
- **Bandit** - HTTP server
- **Req** - Modern HTTP client

---

## 🚀 Getting Started

### Installation

```bash
# Install dependencies
mix setup

# Start Phoenix server
mix phx.server

# Or start inside IEx
iEx -S mix phx.server
```

Now visit [`localhost:4000`](http://localhost:4000) 🎉

---

## 📚 Available Commands

```bash
# Setup database and dependencies
mix setup

# Reset database
mix ecto.reset

# Run tests
mix test

# Run precommit checks (linting, formatting, tests)
mix precommit
```

## Database Management

This app is the master for all database changes.

```
# Create new migration
mix ecto.gen.migration migration_name

# Run migrations
mix ecto.migrate

# Rollback
mix ecto.rollback
```

---

## API Endpoints for Node.js BFF

- POST `/api/jobs/search` — Search for jobs on HH.ru
- POST `/api/applications/submit` — Submit application to HH.ru

### OAuth (HH.ru)
- GET `/auth/hh/redirect` → JSON `{ url, state }`
- GET `/auth/hh/callback?code=...` → exchanges code for `{ access_token, refresh_token, expires_at }`
- POST `/auth/hh/refresh` → body `{ refresh_token }` → new tokens

Token storage table: `hh_tokens` (MVP: plain text; add encryption before production).

Env vars:
```
HH_CLIENT_ID=
HH_CLIENT_SECRET=
HH_REDIRECT_URI=http://localhost:5173/auth/callback
```

---

## 🧪 Development Guidelines

- Use `mix precommit` before committing changes
- Prefer `Req` for HTTP requests
- Keep business logic in `lib/core/`, web in `lib/core_web/`
- Avoid nesting modules in a file (Phoenix 1.8 guidelines)

---

## 📖 Learn More

- Phoenix Framework
- Phoenix Guides
- Phoenix Docs

---

## 📄 License

MIT License © 2025 Aleksandr Sakhatskiy

---

<div align="center">
  Made with 💜 and Elixir
</div>
