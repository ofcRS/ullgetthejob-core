# 🎯 UllGetTheJob Core

> **Phoenix-powered job application platform backend** 🔥  
> Built with Elixir + Phoenix LiveView for real-time, reactive job hunting experiences!

---

## ✨ What's This?

**UllGetTheJob Core** is the heart of the job application tracking platform. This Phoenix application serves as the main backend, handling:

- 🚀 **Real-time updates** with Phoenix LiveView
- 📊 **Job application tracking** and management
- 🔐 **Authentication & authorization** 
- 💾 **PostgreSQL database** integration with Ecto
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
