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
  alias ColouredFlowDashboard.Seeds.IncidentTriageFlow
  alias ColouredFlowDashboard.Seeds.PiAgentFlow
  alias ColouredFlowDashboard.Seeds.TrafficLightFlow

  @flows [ApprovalFlow, IncidentTriageFlow, TrafficLightFlow, PiAgentFlow]

  setup do
    snapshots =
      Map.new(@flows, fn flow ->
        {flow, :persistent_term.get({Seed, flow}, nil)}
      end)

    for {flow, prior} <- snapshots, prior != nil do
      :persistent_term.erase({Seed, flow})
    end

    on_exit(fn ->
      for {flow, prior} <- snapshots do
        if prior do
          :persistent_term.put({Seed, flow}, prior)
        else
          :persistent_term.erase({Seed, flow})
        end
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
    test "inserts both seeded flows + enactments and registers the runner GenServers" do
      assert :ok = Seed.run(enabled: true)

      for flow <- @flows do
        assert enactment_id = Seed.enactment_id(flow)
        assert is_binary(enactment_id)

        assert [{_pid, _value}] =
                 Registry.lookup(EnactmentRegistry, {:enactment, enactment_id})
      end
    end

    test "running twice in the same BEAM is idempotent" do
      assert :ok = Seed.run(enabled: true)
      first_ids = Map.new(@flows, &{&1, Seed.enactment_id(&1)})
      for {_flow, id} <- first_ids, do: assert(is_binary(id))

      assert :ok = Seed.run(enabled: true)
      for flow <- @flows, do: assert(Seed.enactment_id(flow) == first_ids[flow])
    end
  end
end
