import Config

if config_env() == :test do
  config :coloured_flow,
         ColouredFlow.Runner.Storage,
         repo: ColouredFlow.TestRepo

  config :coloured_flow,
    ecto_repos: [ColouredFlow.TestRepo]

  config :coloured_flow, ColouredFlow.TestRepo,
    database: "coloured_flow_test",
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    pool: Ecto.Adapters.SQL.Sandbox
end
