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

### Prerequisites

- Elixir 1.15 or later
- PostgreSQL database
- Erlang/OTP

### Installation

```bash
# Install dependencies
mix setup

# Start Phoenix server
mix phx.server

# Or start inside IEx
iex -S mix phx.server
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

## API Endpoints for Node.js BFF

- POST /api/jobs/search — Search for jobs on HH.ru
- POST /api/applications/submit — Submit application to HH.ru

---

## 🏗️ Project Structure

```
lib/
├── core/              # Core business logic
│   └── ...
├── core_web/          # Web interface (controllers, views, LiveViews)
│   └── ...
├── core.ex            # Application entry point
└── core_web.ex        # Web module definitions
```

---

## 🧪 Development

This project follows Phoenix best practices:

- Use `mix precommit` before committing changes
- Prefer `Req` library for HTTP requests
- Follow Phoenix LiveView patterns for real-time features
- Keep business logic in `lib/core/`
- Keep web logic in `lib/core_web/`

---

## 📖 Learn More

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix Guides](https://hexdocs.pm/phoenix/overview.html)
- [Phoenix Docs](https://hexdocs.pm/phoenix)
- [Elixir Forum](https://elixirforum.com/c/phoenix-forum)

---

## 📄 License

MIT License - Copyright (c) 2025 Aleksandr Sakhatskiy

---

<div align="center">
  Made with 💜 and Elixir
</div>
