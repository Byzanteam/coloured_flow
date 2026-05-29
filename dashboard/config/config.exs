# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :coloured_flow_dashboard,
  ecto_repos: [ColouredFlowDashboard.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :coloured_flow_dashboard, ColouredFlowDashboardWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: ColouredFlowDashboardWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: :coloured_flow_dashboard_pubsub,
  live_view: [signing_salt: "MDUygP2z"]

# Point the coloured_flow runner storage at our Repo so both apps share
# the same DB and pool. `:storage` selects the Ecto-backed default; `:repo`
# is read by `ColouredFlow.Runner.Storage.Repo`'s dispatcher.
config :coloured_flow, ColouredFlow.Runner.Storage,
  storage: ColouredFlow.Runner.Storage.Default,
  repo: ColouredFlowDashboard.Repo

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
