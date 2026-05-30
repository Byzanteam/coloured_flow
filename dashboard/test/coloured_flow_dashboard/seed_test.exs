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

  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlowDashboard.Repo
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

        # Look up via the registry's via-tuple instead of importing the
        # internal Registry module (parity with Seed's `running?/1`).
        via =
          {:via, Registry, {ColouredFlow.Runner.Enactment.Registry, {:enactment, enactment_id}}}

        assert is_pid(GenServer.whereis(via))
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

  # The dedupe (`:reused`) branch only fires on the Default (Postgres)
  # storage backend; the InMemory backend is process-scoped and rebuilt on
  # every boot, so there is no cross-boot path to dedupe. The test env
  # otherwise pins `Storage.InMemory` for speed, so the setup below
  # temporarily flips to `Storage.Default` and restores it on_exit.
  # Safe because the module is `async: false`, which means no concurrent
  # module reads the swapped key while the override is in effect.
  describe "run/1 against the Default (Postgres) backend" do
    setup do
      cfg = Application.fetch_env!(:coloured_flow, ColouredFlow.Runner.Storage)
      original_storage = cfg[:storage]

      Application.put_env(
        :coloured_flow,
        ColouredFlow.Runner.Storage,
        Keyword.put(cfg, :storage, ColouredFlow.Runner.Storage.Default)
      )

      # Earlier tests (and earlier `describe` blocks) leave enactment
      # GenServers under the supervisor. Those processes were booted
      # against the InMemory backend; once we flip the storage env they
      # would crash mid-query against Postgres and pin a sandbox
      # connection. Terminate everything still alive before exercising
      # the Default backend.
      terminate_all_enactments()

      on_exit(fn ->
        terminate_all_enactments()
        restored = Keyword.put(cfg, :storage, original_storage)
        Application.put_env(:coloured_flow, ColouredFlow.Runner.Storage, restored)
      end)

      :ok
    end

    defp terminate_all_enactments do
      sup = ColouredFlow.Runner.Enactment.Supervisor

      for {_id, pid, _type, _mods} <- DynamicSupervisor.which_children(sup), is_pid(pid) do
        DynamicSupervisor.terminate_child(sup, pid)
      end
    end

    test "twice in one BEAM does not duplicate Schemas.Flow / Schemas.Enactment rows" do
      assert :ok = Seed.run(enabled: true)

      flow_count = Repo.aggregate(Schemas.Flow, :count)
      enactment_count = Repo.aggregate(Schemas.Enactment, :count)

      assert flow_count == length(@flows)
      assert enactment_count == length(@flows)

      # Drop the persistent_term cache so the second call must re-derive
      # `flow_id` / `enactment_id` via DB lookup — that is exactly the
      # cross-boot path we are guarding against duplication on.
      for flow <- @flows, do: :persistent_term.erase({Seed, flow})

      assert :ok = Seed.run(enabled: true)

      assert Repo.aggregate(Schemas.Flow, :count) == flow_count
      assert Repo.aggregate(Schemas.Enactment, :count) == enactment_count
    end

    test "cross-boot rerun logs `reused` instead of `seeded`" do
      assert :ok = Seed.run(enabled: true)
      for flow <- @flows, do: :persistent_term.erase({Seed, flow})

      log = with_info_logs(fn -> assert :ok = Seed.run(enabled: true) end)

      for flow <- @flows do
        assert log =~ "reused #{inspect(flow)}"
        refute log =~ "seeded #{inspect(flow)}"
      end
    end
  end

  # Tests live under `config :logger, level: :warning` (see `config/test.exs`),
  # which drops `Logger.info/1` calls before they reach any backend — including
  # `ExUnit.CaptureLog`'s. Lifting the primary level to `:info` for the
  # duration of `fun` is the minimal seam that lets us observe the
  # `:reused` log line.
  defp with_info_logs(fun) do
    original = Logger.level()
    Logger.configure(level: :info)

    try do
      ExUnit.CaptureLog.capture_log(fun)
    after
      Logger.configure(level: original)
    end
  end
end
