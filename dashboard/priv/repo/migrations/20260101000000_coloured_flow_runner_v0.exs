defmodule ColouredFlowDashboard.Repo.Migrations.ColouredFlowRunnerV0 do
  use Ecto.Migration

  def change do
    ColouredFlow.Runner.Migrations.V0.change()
  end
end
