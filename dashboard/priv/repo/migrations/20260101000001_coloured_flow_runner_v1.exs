defmodule ColouredFlowDashboard.Repo.Migrations.ColouredFlowRunnerV1 do
  use Ecto.Migration

  def change do
    ColouredFlow.Runner.Migrations.V1.change()
  end
end
