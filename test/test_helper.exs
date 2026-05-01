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

# Mimic-mockable modules. Tests that want to override behaviour call
# `Mimic.copy/1` on these in their `setup` block (or `use Mimic` at the
# top of the file) and `Mimic.expect/3` per test.
Mimic.copy(Application)

ExUnit.start(capture_log: true)
