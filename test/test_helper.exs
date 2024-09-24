Mix.Task.run("ecto.create")

{:ok, _pid} = ColouredFlow.TestRepo.start_link()
:ok = ColouredFlow.TestRepo.migrate()

Ecto.Adapters.SQL.Sandbox.mode(ColouredFlow.TestRepo, :manual)

ExUnit.start(capture_log: true)
