Mix.Task.run("ecto.create")

repo_config = ColouredFlow.TestRepo.config()

ColouredFlow.TestRepo.__adapter__().storage_down(repo_config)
ColouredFlow.TestRepo.__adapter__().storage_up(repo_config)

{:ok, _pid} = ColouredFlow.Runner.Supervisor.start_link([])
{:ok, _pid} = ColouredFlow.TestRepo.start_link()
:ok = ColouredFlow.TestRepo.migrate()

Ecto.Adapters.SQL.Sandbox.mode(ColouredFlow.TestRepo, :manual)

ExUnit.start(capture_log: true)
