defmodule ColouredFlowDashboard.Repo.Migrations.ColouredFlowRunnerV2 do
  use Ecto.Migration

  def change do
    ColouredFlow.Runner.Migrations.V2.change()
  end
end
