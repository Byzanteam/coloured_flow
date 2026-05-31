defmodule ColouredFlowDashboard.Repo.Migrations.ColouredFlowRunnerV3 do
  use Ecto.Migration

  def change do
    ColouredFlow.Runner.Migrations.V3.change()
  end
end
