if System.get_env("RESET_DB") do
  Mix.Task.run("ecto.drop")
  Mix.Task.run("ecto.create")
else
  # Ensure the database is created
  Mix.Task.run("ecto.create")
end

{:ok, _pid} = ColouredFlow.Runner.Supervisor.start_link([])
{:ok, _pid} = ColouredFlow.TestRepo.start_link()
:ok = ColouredFlow.TestRepo.migrate()

Ecto.Adapters.SQL.Sandbox.mode(ColouredFlow.TestRepo, :manual)

ExUnit.start(capture_log: true)
