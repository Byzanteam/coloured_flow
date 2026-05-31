defmodule Mix.Tasks.Cf.Dashboard.ResetSeedDbTest do
  # async: false because the task TRUNCATEs whole tables under the shared
  # `coloured_flow` schema. The sandbox transaction rolls the truncate
  # back, but two concurrent tests in the same sandbox would still see
  # each other's seed rows wiped mid-test.
  use ColouredFlowDashboard.DataCase, async: false

  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlowDashboard.Repo
  alias ColouredFlowDashboard.Seeds.ApprovalFlow
  alias Mix.Tasks.Cf.Dashboard.ResetSeedDb

  describe "reset!/1" do
    test "refuses to run when MIX_ENV is not :dev" do
      assert_raise Mix.Error, ~r/refuses to run in MIX_ENV=test/, fn ->
        ResetSeedDb.reset!(:test)
      end

      assert_raise Mix.Error, ~r/refuses to run in MIX_ENV=prod/, fn ->
        ResetSeedDb.reset!(:prod)
      end
    end

    test "truncates the seed tables under :dev" do
      flow =
        Repo.insert!(%Schemas.Flow{
          name: "ResetSeedDbTest fixture",
          definition: ApprovalFlow.cpnet()
        })

      assert Repo.aggregate(Schemas.Flow, :count) >= 1
      assert Repo.get(Schemas.Flow, flow.id)

      assert :ok = ResetSeedDb.reset!(:dev)

      assert Repo.aggregate(Schemas.Flow, :count) == 0
      assert Repo.aggregate(Schemas.Enactment, :count) == 0
    end
  end

  describe "run/1" do
    test "delegates to reset!/1 with the current Mix.env() (test → raises)" do
      assert_raise Mix.Error, ~r/refuses to run in MIX_ENV=test/, fn ->
        ResetSeedDb.run([])
      end
    end
  end
end
