# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :core,
  ecto_repos: [Core.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Cloak encryption configuration
config :core, Core.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      # Key will be set in runtime.exs from ENCRYPTION_KEY env var
      key: :base64_key_from_env
    }
  ]

# Guardian JWT authentication
config :core, Core.Auth.Guardian,
  issuer: "core",
  # Secret key will be set in runtime.exs from GUARDIAN_SECRET_KEY env var
  secret_key: :secret_key_from_env,
  ttl: {30, :days},
  allowed_drift: 2000,
  verify_issuer: true,
  serializer: Core.Auth.Guardian

# Oban background job processing
config :core, Oban,
  repo: Core.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 86400},  # Prune jobs older than 1 day
    {Oban.Plugins.Cron, crontab: []}  # Placeholder for future cron jobs
  ],
  queues: [
    hh_api: 5,  # HH.ru API operations, max 5 concurrent
    default: 10  # Default queue for other jobs
  ]

# Configures the endpoint
config :core, CoreWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CoreWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Core.PubSub,
  live_view: [signing_salt: "H5Po1lr2"]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :trace_id, :span_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# OpenTelemetry instrumentation
config :opentelemetry, :resource,
  service: [
    name: "core",
    namespace: "ullgetthejob"
  ]

# OpenTelemetry OTLP exporter
config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_compression: :gzip,
  # Endpoint will be set in runtime.exs
  otlp_endpoint: "http://localhost:4318"

# Instrument Phoenix with OpenTelemetry
config :core, CoreWeb.Endpoint,
  instrumenters: [OpentelemetryPhoenix.Instrumenter]

# Instrument Ecto with OpenTelemetry
config :core, Core.Repo,
  telemetry_prefix: [:core, :repo],
  log: false  # Use OpenTelemetry for logging instead

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
