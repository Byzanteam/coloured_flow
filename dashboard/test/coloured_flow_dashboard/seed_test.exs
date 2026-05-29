defmodule ColouredFlowDashboard.SeedTest do
  # `async: false` is forced because `Seed.run/0` writes to a global
  # `:persistent_term`, mutates `:coloured_flow_dashboard, :seed_flows`,
  # and registers an enactment under the singleton
  # `ColouredFlow.Runner.Enactment.Supervisor`. Tests must serialize so
  # one suite does not observe another's seeded enactment.
  use ColouredFlowDashboard.DataCase, async: false

  alias ColouredFlow.Runner.Enactment.Registry, as: EnactmentRegistry
  alias ColouredFlowDashboard.Seed
  alias ColouredFlowDashboard.Seeds.ApprovalFlow

  setup do
    prior_flag = Application.get_env(:coloured_flow_dashboard, :seed_flows)
    prior_pt = :persistent_term.get({Seed, ApprovalFlow}, nil)
    if prior_pt, do: :persistent_term.erase({Seed, ApprovalFlow})

    on_exit(fn ->
      case prior_flag do
        nil -> Application.delete_env(:coloured_flow_dashboard, :seed_flows)
        value -> Application.put_env(:coloured_flow_dashboard, :seed_flows, value)
      end

      if prior_pt do
        :persistent_term.put({Seed, ApprovalFlow}, prior_pt)
      else
        :persistent_term.erase({Seed, ApprovalFlow})
      end
    end)

    :ok
  end

  describe "run/0 with :seed_flows disabled" do
    test "is a no-op and leaves no persistent_term entry" do
      Application.put_env(:coloured_flow_dashboard, :seed_flows, false)

      assert :ok = Seed.run()
      assert Seed.enactment_id(ApprovalFlow) == nil
    end
  end

  describe "run/0 with :seed_flows enabled" do
    setup do
      Application.put_env(:coloured_flow_dashboard, :seed_flows, true)
      :ok
    end

    test "inserts a flow + enactment and registers the runner GenServer" do
      assert :ok = Seed.run()

      assert enactment_id = Seed.enactment_id(ApprovalFlow)
      assert is_binary(enactment_id)

      assert [{_pid, _value}] =
               Registry.lookup(EnactmentRegistry, {:enactment, enactment_id})
    end

    test "running twice in the same BEAM is idempotent" do
      assert :ok = Seed.run()
      first_id = Seed.enactment_id(ApprovalFlow)
      assert is_binary(first_id)

      assert :ok = Seed.run()
      assert Seed.enactment_id(ApprovalFlow) == first_id
    end
  end
end
