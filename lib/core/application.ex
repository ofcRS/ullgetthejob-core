defmodule Core.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Setup OpenTelemetry (optional - skip if modules not available or incompatible)
    try do
      if Code.ensure_loaded?(:opentelemetry_cowboy) do
        :opentelemetry_cowboy.setup()
      end
      # Note: OpentelemetryPhoenix doesn't support bandit adapter, use nil
      OpentelemetryPhoenix.setup()
      OpentelemetryEcto.setup([:core, :repo])
    rescue
      _ -> :ok
    end

    children = [
      # Telemetry
      CoreWeb.Telemetry,
      # Encryption vault (must start before Repo)
      Core.Vault,
      # Database
      Core.Repo,
      # Background job processing
      {Oban, Application.fetch_env!(:core, Oban)},
      # DNS clustering
      {DNSCluster, query: Application.get_env(:core, :dns_cluster_query) || :ignore},
      # PubSub for Phoenix channels
      {Phoenix.PubSub, name: Core.PubSub},
      # Rate limiter for HH.ru API
      Core.RateLimiter,
      # Jobs orchestrator for periodic fetching
      Core.Jobs.Orchestrator,
      # Start to serve requests, typically the last entry
      CoreWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Core.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CoreWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
