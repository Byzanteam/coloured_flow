import Config

if config_env() == :test do
  config :coloured_flow,
         ColouredFlow.Runner.Enactment,
         timeout: 60 * 1000

  config :coloured_flow,
         ColouredFlow.Runner.Storage,
         repo: ColouredFlow.TestRepo,
         storage: ColouredFlow.Runner.Storage.Default

  config :coloured_flow,
    ecto_repos: [ColouredFlow.TestRepo]

  config :coloured_flow, ColouredFlow.TestRepo,
    database: "coloured_flow_test",
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    pool: Ecto.Adapters.SQL.Sandbox
end
