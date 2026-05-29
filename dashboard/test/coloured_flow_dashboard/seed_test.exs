defmodule ColouredFlowDashboard.SeedTest do
  # `async: false` because `Seed.run/1` writes to a global `:persistent_term`
  # and registers an enactment under the singleton
  # `ColouredFlow.Runner.Enactment.Supervisor`. Tests must serialize so one
  # case does not observe another's seeded enactment.
  #
  # The gate is now passed via `Seed.run(enabled: true)` rather than mutating
  # the shared `:coloured_flow_dashboard, :seed_flows` runtime config key, so
  # no cross-test `Application.put_env` leak.
  use ColouredFlowDashboard.DataCase, async: false

  alias ColouredFlow.Runner.Enactment.Registry, as: EnactmentRegistry
  alias ColouredFlowDashboard.Seed
  alias ColouredFlowDashboard.Seeds.ApprovalFlow

  setup do
    prior_pt = :persistent_term.get({Seed, ApprovalFlow}, nil)
    if prior_pt, do: :persistent_term.erase({Seed, ApprovalFlow})

    on_exit(fn ->
      if prior_pt do
        :persistent_term.put({Seed, ApprovalFlow}, prior_pt)
      else
        :persistent_term.erase({Seed, ApprovalFlow})
      end
    end)

    :ok
  end

  describe "run/1 with enabled: false" do
    test "is a no-op and leaves no persistent_term entry" do
      assert :ok = Seed.run(enabled: false)
      assert Seed.enactment_id(ApprovalFlow) == nil
    end
  end

  describe "run/1 with enabled: true" do
    test "inserts a flow + enactment and registers the runner GenServer" do
      assert :ok = Seed.run(enabled: true)

      assert enactment_id = Seed.enactment_id(ApprovalFlow)
      assert is_binary(enactment_id)

      assert [{_pid, _value}] =
               Registry.lookup(EnactmentRegistry, {:enactment, enactment_id})
    end

    test "running twice in the same BEAM is idempotent" do
      assert :ok = Seed.run(enabled: true)
      first_id = Seed.enactment_id(ApprovalFlow)
      assert is_binary(first_id)

      assert :ok = Seed.run(enabled: true)
      assert Seed.enactment_id(ApprovalFlow) == first_id
    end
  end
end
