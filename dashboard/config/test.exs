import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :coloured_flow_dashboard, ColouredFlowDashboard.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "coloured_flow_dashboard_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Use the in-memory ETS-backed runner storage in tests so the bridge +
# integration smoke can drive enactments without a Postgres round-trip.
# The dashboard's Application picks up `InMemory` and inserts the GenServer
# ahead of `Runner.Supervisor` in the child list.
config :coloured_flow, ColouredFlow.Runner.Storage,
  storage: ColouredFlow.Runner.Storage.InMemory,
  repo: ColouredFlowDashboard.Repo

# Disable the boot-time enactment resumer in tests. Most tests do not want a
# real sweep pinging Storage at app start; the dedicated
# `ColouredFlowDashboard.EnactmentResumerTest` starts the GenServer
# explicitly with `enabled: true`.
config :coloured_flow_dashboard, :resume_enactments, false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :coloured_flow_dashboard, ColouredFlowDashboardWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Lpo1Xyy/ZzYV+XMiUbL4uKF+0h7LNT10aU3T9s6cYxZeaM1i1x/54AD6OgUqv2Cx",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
