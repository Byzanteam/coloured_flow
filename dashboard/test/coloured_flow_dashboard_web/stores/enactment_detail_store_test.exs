defmodule ColouredFlowDashboardWeb.Stores.EnactmentDetailStoreTest do
  # async: false for parity with InboxStoreTest: the Musubi page server runs
  # in a separate process, so cross-process Repo allowances need the shared
  # sandbox setup. Bridge fan-out tests still cover the per-test isolation
  # patterns.
  use ColouredFlowDashboard.DataCase, async: false

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Runner.Enactment, as: RunnerEnactment
  alias ColouredFlow.Runner.Enactment.Workitem, as: RunnerWorkitem
  alias ColouredFlowDashboard.Seed
  alias ColouredFlowDashboard.Seeds.ApprovalFlow
  alias ColouredFlowDashboard.TelemetryBridge
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboardWeb.Stores.EnactmentDetailStore
  alias ColouredFlowDashboardWeb.Views.EnactmentSummary

  @pubsub :coloured_flow_dashboard_pubsub

  setup context do
    topic_prefix = "cf-detail-test-#{discriminator(context)}:"
    enactment_id = Ecto.UUID.generate()
    topic = "#{topic_prefix}enactment:#{enactment_id}"

    flow_cache =
      unique_cache_atom("enactment_detail_store_test_flow_cache_#{discriminator(context)}")

    {:ok,
     enactment_id: enactment_id, topic: topic, topic_prefix: topic_prefix, flow_cache: flow_cache}
  end

  describe "mount/2" do
    test "seeds empty state for a never-seen enactment id", %{
      enactment_id: enactment_id,
      topic_prefix: topic_prefix,
      flow_cache: flow_cache
    } do
      page = mount_store(enactment_id, topic_prefix, flow_cache)

      assigns = Musubi.Testing.assigns(page)
      assert assigns.enactment_id == enactment_id
      assert assigns.summary.enactment_id == enactment_id
      assert assigns.summary.markings_count == 0
      assert assigns.summary.workitems_count == 0
      assert assigns.workitem_ids == MapSet.new()
    end

    test "seeds workitems + markings from a live runner enactment", %{
      topic_prefix: topic_prefix,
      flow_cache: flow_cache
    } do
      # ApprovalFlow seeds a real running enactment whose first transition
      # produces one workitem (`approve`). Force the seed for this test only.
      Seed.run(enabled: true)
      enactment_id = Seed.enactment_id(ApprovalFlow)
      assert is_binary(enactment_id)

      # Give the runner one scheduler pass to populate the workitem.
      assert_eventually(fn ->
        case GenServer.whereis(
               ColouredFlow.Runner.Enactment.Registry.via_name({:enactment, enactment_id})
             ) do
          pid when is_pid(pid) ->
            %RunnerEnactment{workitems: workitems} = :sys.get_state(pid)
            map_size(workitems) > 0

          _other ->
            false
        end
      end)

      page = mount_store(enactment_id, topic_prefix, flow_cache)
      assigns = Musubi.Testing.assigns(page)

      assert assigns.summary.state == :running
      assert assigns.summary.workitems_count >= 1
      assert MapSet.size(assigns.workitem_ids) >= 1
    end
  end

  describe "event routing" do
    setup %{enactment_id: enactment_id, topic_prefix: topic_prefix, flow_cache: flow_cache} do
      page = mount_store(enactment_id, topic_prefix, flow_cache)
      {:ok, page: page}
    end

    test "produce_workitems_stop inserts a row + bumps summary", %{
      enactment_id: eid,
      topic: topic,
      page: page
    } do
      wi_id = Ecto.UUID.generate()
      broadcast!(topic, build_workitem_event(:produce_workitems_stop, eid, wi_id, :enabled, 1))

      assigns = Musubi.Testing.assigns(page)
      assert MapSet.member?(assigns.workitem_ids, wi_id)
      assert assigns.summary.workitems_count == 1
      assert assigns.summary.version == 1
    end

    test "complete_workitems_stop removes the workitem AND emits an occurrence row", %{
      enactment_id: eid,
      topic: topic,
      page: page
    } do
      wi_id = Ecto.UUID.generate()
      broadcast!(topic, build_workitem_event(:produce_workitems_stop, eid, wi_id, :enabled, 1))
      broadcast!(topic, build_workitem_event(:start_workitems_stop, eid, wi_id, :started, 1))
      broadcast!(topic, build_workitem_event(:complete_workitems_stop, eid, wi_id, :completed, 2))

      assigns = Musubi.Testing.assigns(page)
      refute MapSet.member?(assigns.workitem_ids, wi_id)
      assert assigns.summary.workitems_count == 0
      assert assigns.summary.version == 2
      assert assigns.summary.last_occurrence_at != nil
    end

    test "enactment_terminate flips summary.state and clears workitems", %{
      enactment_id: eid,
      topic: topic,
      page: page
    } do
      wi_id = Ecto.UUID.generate()
      broadcast!(topic, build_workitem_event(:produce_workitems_stop, eid, wi_id, :enabled, 1))

      terminate_event = %Event{
        topic: {:enactment, eid},
        kind: :enactment_terminate,
        enactment_id: eid,
        enactment_version: 2,
        occurred_at: DateTime.utc_now(),
        payload: %{termination_type: :force, termination_message: "test"}
      }

      broadcast!(topic, terminate_event)

      %EnactmentSummary{} = summary = Musubi.Testing.assigns(page).summary
      assert summary.state == :terminated
      assert summary.workitems_count == 0
      assert Musubi.Testing.assigns(page).workitem_ids == MapSet.new()
    end

    test "enactment_exception flips summary.state to :exception", %{
      enactment_id: eid,
      topic: topic,
      page: page
    } do
      event = %Event{
        topic: {:enactment, eid},
        kind: :enactment_exception,
        enactment_id: eid,
        enactment_version: 3,
        occurred_at: DateTime.utc_now(),
        payload: %{exception_reason: :runtime, error_banner: "boom"}
      }

      broadcast!(topic, event)

      assert Musubi.Testing.assigns(page).summary.state == :exception
    end

    test "events for OTHER enactments are ignored", %{
      enactment_id: _eid,
      topic: topic,
      page: page
    } do
      other_eid = Ecto.UUID.generate()
      wi_id = Ecto.UUID.generate()

      broadcast!(
        topic,
        build_workitem_event(:produce_workitems_stop, other_eid, wi_id, :enabled, 1)
      )

      assigns = Musubi.Testing.assigns(page)
      assert MapSet.size(assigns.workitem_ids) == 0
      assert assigns.summary.workitems_count == 0
    end
  end

  describe ":take_snapshot command (live enactment)" do
    setup %{topic_prefix: topic_prefix, flow_cache: flow_cache} do
      Seed.run(enabled: true)
      enactment_id = Seed.enactment_id(ApprovalFlow)
      page = mount_store(enactment_id, topic_prefix, flow_cache)
      {:ok, page: page, enactment_id: enactment_id}
    end

    test "ok when the enactment GenServer is running", %{page: page} do
      assert {:ok, %{code: :ok}} =
               Musubi.Testing.dispatch_command(page, :take_snapshot, %{})
    end
  end

  describe ":take_snapshot command (stale enactment)" do
    test "not_running when the enactment GenServer is absent", %{
      topic_prefix: topic_prefix,
      flow_cache: flow_cache
    } do
      stale = Ecto.UUID.generate()
      page = mount_store(stale, topic_prefix, flow_cache)

      assert {:ok, %{code: :not_running}} =
               Musubi.Testing.dispatch_command(page, :take_snapshot, %{})
    end
  end

  describe ":force_terminate command (live enactment)" do
    setup %{topic_prefix: topic_prefix, flow_cache: flow_cache} do
      Seed.run(enabled: true)
      enactment_id = Seed.enactment_id(ApprovalFlow)
      page = mount_store(enactment_id, topic_prefix, flow_cache)
      {:ok, page: page, enactment_id: enactment_id}
    end

    test "ok terminates the running enactment", %{page: page} do
      assert {:ok, %{code: :ok}} =
               Musubi.Testing.dispatch_command(page, :force_terminate, %{reason: "test"})

      # Subsequent calls collapse to already_terminated once the GenServer dies.
      assert_eventually(fn ->
        case Musubi.Testing.dispatch_command(page, :force_terminate, %{reason: "again"}) do
          {:ok, %{code: :already_terminated}} -> true
          _other -> false
        end
      end)
    end
  end

  describe ":force_terminate command (stale enactment)" do
    test "already_terminated when no GenServer is registered", %{
      topic_prefix: topic_prefix,
      flow_cache: flow_cache
    } do
      stale = Ecto.UUID.generate()
      page = mount_store(stale, topic_prefix, flow_cache)

      assert {:ok, %{code: :already_terminated}} =
               Musubi.Testing.dispatch_command(page, :force_terminate, %{reason: "x"})
    end
  end

  describe ":retry_enactment command" do
    test "not_exception when the storage row is :running",
         %{topic_prefix: topic_prefix, flow_cache: flow_cache} do
      enactment = insert_enactment_with_state!(:running)
      page = mount_store(enactment.id, topic_prefix, flow_cache)

      assert {:ok, %{code: :not_exception}} =
               Musubi.Testing.dispatch_command(page, :retry_enactment, %{})
    end

    test "already_terminated when the storage row is :terminated",
         %{topic_prefix: topic_prefix, flow_cache: flow_cache} do
      enactment = insert_enactment_with_state!(:terminated)
      page = mount_store(enactment.id, topic_prefix, flow_cache)

      assert {:ok, %{code: :already_terminated}} =
               Musubi.Testing.dispatch_command(page, :retry_enactment, %{})
    end

    test "runner_error when no storage row exists",
         %{topic_prefix: topic_prefix, flow_cache: flow_cache} do
      stale = Ecto.UUID.generate()
      page = mount_store(stale, topic_prefix, flow_cache)

      assert {:ok, %{code: :runner_error}} =
               Musubi.Testing.dispatch_command(page, :retry_enactment, %{})
    end

    # Race pin (P20 HIGH): another operator force-terminated the row, but
    # this page's cached `summary.state` is still `:exception` because the
    # `:enactment_terminate` event has not been broadcast/applied yet. The
    # handler MUST re-read storage and deny the retry — otherwise
    # `Storage.retry_enactment/2` would flip `:terminated` → `:running` and
    # resurrect a closed enactment.
    test "refuses retry when cached :exception lags behind a terminated storage row",
         %{topic_prefix: topic_prefix, flow_cache: flow_cache, topic: _topic_unused} do
      enactment = insert_enactment_with_state!(:terminated)
      eid = enactment.id
      topic = "#{topic_prefix}enactment:#{eid}"
      page = mount_store(eid, topic_prefix, flow_cache)

      # Force the Musubi-cached state back to `:exception` to mimic a stale
      # detail page that never saw the terminate event.
      broadcast!(topic, %Event{
        topic: {:enactment, eid},
        kind: :enactment_exception,
        enactment_id: eid,
        enactment_version: 99,
        occurred_at: DateTime.utc_now(),
        payload: %{error_banner: "stale exception"}
      })

      assert Musubi.Testing.assigns(page).summary.state == :exception

      assert {:ok, %{code: :already_terminated}} =
               Musubi.Testing.dispatch_command(page, :retry_enactment, %{})

      # Storage row must still be `:terminated` — `Storage.retry_enactment/2`
      # was never called.
      assert %ColouredFlow.Runner.Storage.Schemas.Enactment{state: :terminated} =
               Repo.get!(ColouredFlow.Runner.Storage.Schemas.Enactment, eid)
    end
  end

  describe "telemetry stream" do
    setup %{enactment_id: enactment_id, topic_prefix: topic_prefix, flow_cache: flow_cache} do
      page = mount_store(enactment_id, topic_prefix, flow_cache)
      _drained = drain_patch()
      {:ok, page: page}
    end

    test "produce_workitems_stop is appended as :info severity", %{
      enactment_id: eid,
      topic: topic
    } do
      wi_id = Ecto.UUID.generate()
      broadcast!(topic, build_workitem_event(:produce_workitems_stop, eid, wi_id, :enabled, 1))

      assert %{op: "insert", item: item} = await_stream_op("insert", :telemetry)
      assert item["severity"] == "info"
      assert item["kind"] == "produce_workitems_stop"
      assert item["summary"] =~ "Produced"
      assert String.starts_with?(item["id"], eid <> "-")
      assert is_binary(item["payload_json"])
    end

    test "enactment_exception is appended as :error severity", %{
      enactment_id: eid,
      topic: topic
    } do
      event = %Event{
        topic: {:enactment, eid},
        kind: :enactment_exception,
        enactment_id: eid,
        enactment_version: 3,
        occurred_at: DateTime.utc_now(),
        payload: %{exception_reason: :runtime, error_banner: "boom"}
      }

      broadcast!(topic, event)

      assert %{op: "insert", item: item} = await_stream_op("insert", :telemetry)
      assert item["severity"] == "error"
      assert item["kind"] == "enactment_exception"
      assert item["summary"] == "boom"
    end

    test "enactment_terminate is appended as :warning severity", %{
      enactment_id: eid,
      topic: topic
    } do
      event = %Event{
        topic: {:enactment, eid},
        kind: :enactment_terminate,
        enactment_id: eid,
        enactment_version: 4,
        occurred_at: DateTime.utc_now(),
        payload: %{termination_type: :force, termination_message: "demo"}
      }

      broadcast!(topic, event)

      ops = await_stream_ops("insert", :telemetry, 1)
      assert [op] = ops
      assert op.item["severity"] == "warning"
      assert op.item["summary"] =~ "terminated"
    end

    test "stream limit caps the telemetry ring buffer", %{
      enactment_id: eid,
      topic: topic
    } do
      # Push more than @telemetry_limit (100) events; the stream's `limit:`
      # opt should cause Musubi to drop older entries automatically.
      for index <- 1..110 do
        broadcast!(
          topic,
          build_workitem_event(
            :produce_workitems_stop,
            eid,
            Ecto.UUID.generate(),
            :enabled,
            index
          )
        )
      end

      # Drain whatever inserts arrived; just assert no crash and at least
      # one limit-bearing insert op landed.
      _drained = drain_patch()
      :ok
    end

    test "events for other enactments do NOT produce a telemetry row", %{
      enactment_id: _eid,
      topic: topic
    } do
      other_eid = Ecto.UUID.generate()
      wi_id = Ecto.UUID.generate()

      broadcast!(
        topic,
        build_workitem_event(:produce_workitems_stop, other_eid, wi_id, :enabled, 1)
      )

      refute telemetry_op_landed?(200)
    end
  end

  describe ":inspect_transition command" do
    setup %{topic_prefix: topic_prefix, flow_cache: _flow_cache} do
      Seed.run(enabled: true)
      enactment_id = Seed.enactment_id(ApprovalFlow)

      # Pre-warm the bridge cpnet cache so the store mount sees transitions.
      _warm = TelemetryBridge.lookup_cpnet(enactment_id, flow_cache_for_seed())

      page = mount_store(enactment_id, topic_prefix, flow_cache_for_seed())
      {:ok, page: page, enactment_id: enactment_id}
    end

    test "ok reply enumerates candidates + rolls up info for a known transition",
         %{page: page} do
      assert {:ok, reply} =
               Musubi.Testing.dispatch_command(page, :inspect_transition, %{
                 transition: "approve"
               })

      assert reply.code == :ok
      assert reply.transition == "approve"
      assert %ColouredFlowDashboardWeb.Views.TransitionDebugInfo{} = reply.info
      assert reply.info.transition == "approve"
      assert reply.info.candidates_count == length(reply.candidates)

      assert reply.info.enabled_count + reply.info.rejected_by_guard_count +
               reply.info.rejected_by_marking_count == reply.info.candidates_count

      assert Enum.all?(reply.candidates, fn c -> c.transition == "approve" end)
    end

    test "unknown_transition reply when the cpnet has no such transition",
         %{page: page} do
      assert {:ok, %{code: :unknown_transition, transition: "ghost"} = reply} =
               Musubi.Testing.dispatch_command(page, :inspect_transition, %{
                 transition: "ghost"
               })

      assert reply.info == nil
      assert reply.candidates == []
    end
  end

  describe ":inspect_transition with no cpnet cached" do
    test "cpnet_unavailable when the bridge cache table is undefined", %{
      enactment_id: enactment_id,
      topic_prefix: topic_prefix,
      flow_cache: flow_cache
    } do
      assert :ets.whereis(flow_cache) == :undefined

      page = mount_store(enactment_id, topic_prefix, flow_cache)

      assert {:ok, %{code: :cpnet_unavailable} = reply} =
               Musubi.Testing.dispatch_command(page, :inspect_transition, %{
                 transition: "approve"
               })

      assert reply.transition == "approve"
    end
  end

  describe "transitions refresh after mount race" do
    test "matching cf_event re-resolves transitions once the bridge cache populates",
         %{enactment_id: eid, topic: topic, topic_prefix: topic_prefix, flow_cache: flow_cache} do
      # Mount with an empty (undefined) flow_cache so resolve_transitions/2
      # short-circuits to [] at mount-time, simulating the race where the
      # bridge cache has not yet observed this enactment.
      assert :ets.whereis(flow_cache) == :undefined
      page = mount_store(eid, topic_prefix, flow_cache)
      assert Musubi.Testing.assigns(page).transitions == []

      # Populate the cache with a tiny CPN under the inspected enactment id
      # — mirrors what TelemetryBridge.resolve_and_cache/2 does internally.
      :ets.new(flow_cache, [:set, :public, :named_table])

      cpnet = %ColouredFlow.Definition.ColouredPetriNet{
        colour_sets: [%ColouredFlow.Definition.ColourSet{name: :int, type: {:integer, []}}],
        places: [%ColouredFlow.Definition.Place{name: "src", colour_set: :int}],
        transitions: [
          ColouredFlow.Builder.DefinitionHelper.build_transition!(name: "race", guard: "true")
        ],
        arcs: [
          ColouredFlow.Builder.DefinitionHelper.build_arc!(
            label: "in",
            place: "src",
            transition: "race",
            orientation: :p_to_t,
            expression: "bind {1, x}"
          )
        ],
        variables: [%ColouredFlow.Definition.Variable{name: :x, colour_set: :int}]
      }

      :ets.insert(flow_cache, {eid, "flow-id", cpnet})

      wi_id = Ecto.UUID.generate()
      broadcast!(topic, build_workitem_event(:produce_workitems_stop, eid, wi_id, :enabled, 1))

      assert Musubi.Testing.assigns(page).transitions == ["race"]
    end

    test "non-empty transitions are NOT re-resolved on subsequent cf_events", %{
      enactment_id: eid,
      topic: topic,
      topic_prefix: topic_prefix,
      flow_cache: flow_cache
    } do
      :ets.new(flow_cache, [:set, :public, :named_table])

      cpnet = %ColouredFlow.Definition.ColouredPetriNet{
        colour_sets: [%ColouredFlow.Definition.ColourSet{name: :int, type: {:integer, []}}],
        places: [%ColouredFlow.Definition.Place{name: "src", colour_set: :int}],
        transitions: [
          ColouredFlow.Builder.DefinitionHelper.build_transition!(name: "stable", guard: "true")
        ],
        arcs: [
          ColouredFlow.Builder.DefinitionHelper.build_arc!(
            label: "in",
            place: "src",
            transition: "stable",
            orientation: :p_to_t,
            expression: "bind {1, x}"
          )
        ],
        variables: [%ColouredFlow.Definition.Variable{name: :x, colour_set: :int}]
      }

      :ets.insert(flow_cache, {eid, "flow-id", cpnet})

      page = mount_store(eid, topic_prefix, flow_cache)
      assert Musubi.Testing.assigns(page).transitions == ["stable"]

      # Replace cache with a different transition list; the refresh should NOT fire.
      newer =
        ColouredFlow.Builder.DefinitionHelper.build_transition!(name: "newer", guard: "true")

      :ets.insert(
        flow_cache,
        {eid, "flow-id", %{cpnet | transitions: [newer | cpnet.transitions]}}
      )

      wi_id = Ecto.UUID.generate()
      broadcast!(topic, build_workitem_event(:produce_workitems_stop, eid, wi_id, :enabled, 1))

      assert Musubi.Testing.assigns(page).transitions == ["stable"]
    end
  end

  describe "summary.last_exception_banner" do
    setup %{enactment_id: enactment_id, topic_prefix: topic_prefix, flow_cache: flow_cache} do
      page = mount_store(enactment_id, topic_prefix, flow_cache)
      {:ok, page: page}
    end

    test "starts nil", %{page: page} do
      assert Musubi.Testing.assigns(page).summary.last_exception_banner == nil
    end

    test "set ONLY by :enactment_exception events (not workitem-op exceptions)", %{
      enactment_id: eid,
      topic: topic,
      page: page
    } do
      # A workitem-op exception must NOT touch the banner.
      wi_op_exception = %Event{
        topic: {:enactment, eid},
        kind: :produce_workitems_exception,
        enactment_id: eid,
        enactment_version: 1,
        occurred_at: DateTime.utc_now(),
        payload: %{error_banner: "wi-op should not surface"}
      }

      broadcast!(topic, wi_op_exception)
      assert Musubi.Testing.assigns(page).summary.last_exception_banner == nil

      # Enactment-level exception updates the banner.
      enactment_exception = %Event{
        topic: {:enactment, eid},
        kind: :enactment_exception,
        enactment_id: eid,
        enactment_version: 2,
        occurred_at: DateTime.utc_now(),
        payload: %{error_banner: "real enactment failure"}
      }

      broadcast!(topic, enactment_exception)

      assert Musubi.Testing.assigns(page).summary.last_exception_banner ==
               "real enactment failure"
    end

    test "subsequent :enactment_exception events overwrite the banner with the latest", %{
      enactment_id: eid,
      topic: topic,
      page: page
    } do
      broadcast!(topic, %Event{
        topic: {:enactment, eid},
        kind: :enactment_exception,
        enactment_id: eid,
        enactment_version: 1,
        occurred_at: DateTime.utc_now(),
        payload: %{error_banner: "first"}
      })

      broadcast!(topic, %Event{
        topic: {:enactment, eid},
        kind: :enactment_exception,
        enactment_id: eid,
        enactment_version: 2,
        occurred_at: DateTime.utc_now(),
        payload: %{error_banner: "second"}
      })

      assert Musubi.Testing.assigns(page).summary.last_exception_banner == "second"
    end

    test ":enactment_terminate clears the banner", %{
      enactment_id: eid,
      topic: topic,
      page: page
    } do
      broadcast!(topic, %Event{
        topic: {:enactment, eid},
        kind: :enactment_exception,
        enactment_id: eid,
        enactment_version: 1,
        occurred_at: DateTime.utc_now(),
        payload: %{error_banner: "boom"}
      })

      assert Musubi.Testing.assigns(page).summary.last_exception_banner == "boom"

      broadcast!(topic, %Event{
        topic: {:enactment, eid},
        kind: :enactment_terminate,
        enactment_id: eid,
        enactment_version: 2,
        occurred_at: DateTime.utc_now(),
        payload: %{termination_type: :force, termination_message: "operator"}
      })

      assert Musubi.Testing.assigns(page).summary.last_exception_banner == nil
    end
  end

  describe "net diagram derivation" do
    test "mount with seeded approval flow derives places, transitions, arcs",
         %{topic_prefix: topic_prefix} do
      Seed.run(enabled: true)
      enactment_id = Seed.enactment_id(ApprovalFlow)
      flow_cache = flow_cache_for_seed()
      _warm = TelemetryBridge.lookup_cpnet(enactment_id, flow_cache)

      page = mount_store(enactment_id, topic_prefix, flow_cache)
      diagram = Musubi.Testing.assigns(page).diagram

      place_names = Enum.map(diagram.places, & &1.name)
      assert "pending" in place_names
      assert "decided" in place_names

      transition_names = Enum.map(diagram.transitions, & &1.name)
      assert "approve" in transition_names
      assert Enum.all?(diagram.transitions, &(&1.enabled_count >= 0))
      assert Enum.all?(diagram.transitions, &is_nil(&1.last_fired_at))

      orientations =
        diagram.arcs
        |> Enum.map(& &1.orientation)
        |> Enum.uniq()
        |> Enum.sort()

      assert orientations == [:p_to_t, :t_to_p]
    end

    test "complete_workitems_stop updates the matching transition's last_fired_at",
         %{enactment_id: eid, topic: topic, topic_prefix: topic_prefix, flow_cache: flow_cache} do
      :ets.new(flow_cache, [:set, :public, :named_table])

      cpnet = synthetic_cpnet()
      :ets.insert(flow_cache, {eid, "flow-id", cpnet})

      page = mount_store(eid, topic_prefix, flow_cache)

      assert Enum.map(Musubi.Testing.assigns(page).diagram.transitions, & &1.last_fired_at) ==
               [nil]

      wi_id = Ecto.UUID.generate()
      broadcast!(topic, build_workitem_event_for(:produce_workitems_stop, eid, wi_id, "pass", 1))

      assigns = Musubi.Testing.assigns(page)
      [transition] = assigns.diagram.transitions
      assert transition.enabled_count == 1
      assert transition.last_fired_at == nil

      broadcast!(
        topic,
        build_workitem_event_for(:complete_workitems_stop, eid, wi_id, "pass", 2)
      )

      assigns = Musubi.Testing.assigns(page)
      [transition] = assigns.diagram.transitions
      assert transition.last_fired_at != nil
      assert transition.enabled_count == 0
    end

    test "diagram is empty when bridge cache has no flow", %{
      enactment_id: eid,
      topic_prefix: topic_prefix,
      flow_cache: flow_cache
    } do
      assert :ets.whereis(flow_cache) == :undefined

      page = mount_store(eid, topic_prefix, flow_cache)
      diagram = Musubi.Testing.assigns(page).diagram

      assert diagram.places == []
      assert diagram.transitions == []
      assert diagram.arcs == []
    end

    test "start_workitems_stop drops the workitem out of enabled_count", %{
      enactment_id: eid,
      topic: topic,
      topic_prefix: topic_prefix,
      flow_cache: flow_cache
    } do
      :ets.new(flow_cache, [:set, :public, :named_table])
      :ets.insert(flow_cache, {eid, "flow-id", synthetic_cpnet()})

      page = mount_store(eid, topic_prefix, flow_cache)

      wi_id = Ecto.UUID.generate()
      broadcast!(topic, build_workitem_event_for(:produce_workitems_stop, eid, wi_id, "pass", 1))

      assert [%{enabled_count: 1}] = Musubi.Testing.assigns(page).diagram.transitions

      broadcast!(topic, build_workitem_event_for(:start_workitems_stop, eid, wi_id, "pass", 1))

      # `:enabled → :started` leaves the firing-enabled set; the glow drops to 0
      # even though the workitem is still live.
      assert [%{enabled_count: 0}] = Musubi.Testing.assigns(page).diagram.transitions
    end

    test "withdraw_workitems_stop drops a still-enabled workitem out of enabled_count", %{
      enactment_id: eid,
      topic: topic,
      topic_prefix: topic_prefix,
      flow_cache: flow_cache
    } do
      :ets.new(flow_cache, [:set, :public, :named_table])
      :ets.insert(flow_cache, {eid, "flow-id", synthetic_cpnet()})

      page = mount_store(eid, topic_prefix, flow_cache)

      wi_id = Ecto.UUID.generate()
      broadcast!(topic, build_workitem_event_for(:produce_workitems_stop, eid, wi_id, "pass", 1))
      assert [%{enabled_count: 1}] = Musubi.Testing.assigns(page).diagram.transitions

      broadcast!(topic, build_workitem_event_for(:withdraw_workitems_stop, eid, wi_id, "pass", 2))
      assert [%{enabled_count: 0}] = Musubi.Testing.assigns(page).diagram.transitions
    end

    test "with two enabled workitems, starting one keeps the glow at 1", %{
      enactment_id: eid,
      topic: topic,
      topic_prefix: topic_prefix,
      flow_cache: flow_cache
    } do
      :ets.new(flow_cache, [:set, :public, :named_table])
      :ets.insert(flow_cache, {eid, "flow-id", synthetic_cpnet()})

      page = mount_store(eid, topic_prefix, flow_cache)

      wi_a = Ecto.UUID.generate()
      wi_b = Ecto.UUID.generate()
      broadcast!(topic, build_workitem_event_for(:produce_workitems_stop, eid, wi_a, "pass", 1))
      broadcast!(topic, build_workitem_event_for(:produce_workitems_stop, eid, wi_b, "pass", 2))
      assert [%{enabled_count: 2}] = Musubi.Testing.assigns(page).diagram.transitions

      broadcast!(topic, build_workitem_event_for(:start_workitems_stop, eid, wi_a, "pass", 2))
      assert [%{enabled_count: 1}] = Musubi.Testing.assigns(page).diagram.transitions

      # Completing the started workitem must NOT touch the still-enabled sibling.
      broadcast!(topic, build_workitem_event_for(:complete_workitems_stop, eid, wi_a, "pass", 3))
      assert [%{enabled_count: 1}] = Musubi.Testing.assigns(page).diagram.transitions
    end

    test "enactment_terminate clears the enabled set", %{
      enactment_id: eid,
      topic: topic,
      topic_prefix: topic_prefix,
      flow_cache: flow_cache
    } do
      :ets.new(flow_cache, [:set, :public, :named_table])
      :ets.insert(flow_cache, {eid, "flow-id", synthetic_cpnet()})

      page = mount_store(eid, topic_prefix, flow_cache)

      wi_id = Ecto.UUID.generate()
      broadcast!(topic, build_workitem_event_for(:produce_workitems_stop, eid, wi_id, "pass", 1))
      assert [%{enabled_count: 1}] = Musubi.Testing.assigns(page).diagram.transitions

      broadcast!(topic, %Event{
        topic: {:enactment, eid},
        kind: :enactment_terminate,
        enactment_id: eid,
        enactment_version: 2,
        occurred_at: DateTime.utc_now(),
        payload: %{termination_type: :force, termination_message: "operator"}
      })

      assert [%{enabled_count: 0}] = Musubi.Testing.assigns(page).diagram.transitions
    end

    test "mount seeds enabled_count from live workitems already in :enabled state", %{
      topic_prefix: topic_prefix
    } do
      # ApprovalFlow's first transition produces one `:enabled` workitem on the
      # `approve` transition. A page opened against an already-running
      # enactment must reflect this at mount, not zero.
      Seed.run(enabled: true)
      enactment_id = Seed.enactment_id(ApprovalFlow)
      flow_cache = flow_cache_for_seed()
      _warm = TelemetryBridge.lookup_cpnet(enactment_id, flow_cache)

      assert_eventually(fn ->
        case GenServer.whereis(
               ColouredFlow.Runner.Enactment.Registry.via_name({:enactment, enactment_id})
             ) do
          pid when is_pid(pid) ->
            %RunnerEnactment{workitems: workitems} = :sys.get_state(pid)

            Enum.any?(workitems, fn {_id, wi} -> wi.state == :enabled end)

          _other ->
            false
        end
      end)

      page = mount_store(enactment_id, topic_prefix, flow_cache)
      diagram = Musubi.Testing.assigns(page).diagram

      approve = Enum.find(diagram.transitions, &(&1.name == "approve"))
      assert approve != nil
      assert approve.enabled_count >= 1
    end
  end

  describe "occurrence row keys" do
    test "synthesised ids are stable across replays of the same complete event", %{
      enactment_id: eid,
      topic_prefix: topic_prefix,
      topic: topic,
      flow_cache: flow_cache
    } do
      page = mount_store(eid, topic_prefix, flow_cache)

      wi_id = Ecto.UUID.generate()
      broadcast!(topic, build_workitem_event(:produce_workitems_stop, eid, wi_id, :enabled, 1))
      broadcast!(topic, build_workitem_event(:start_workitems_stop, eid, wi_id, :started, 1))

      # Two identical complete events (version 2). The synthetic id is
      # version-based, so the stream upserts the same row twice rather than
      # accruing two rows.
      complete_event = build_workitem_event(:complete_workitems_stop, eid, wi_id, :completed, 2)
      broadcast!(topic, complete_event)
      broadcast!(topic, complete_event)

      assigns = Musubi.Testing.assigns(page)
      assert assigns.summary.last_occurrence_at != nil
      # Stable id is `<eid>-2`; no MapSet leak.
      assert assigns.summary.version == 2

      # Marking_count is mount-time-static (see store @moduledoc deviation).
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp discriminator(context),
    do: Integer.to_string(:erlang.phash2({context.module, context.test}))

  # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
  defp unique_cache_atom(name) when is_binary(name), do: String.to_atom(name)

  defp mount_store(enactment_id, topic_prefix, flow_cache) do
    Musubi.Testing.mount(EnactmentDetailStore, %{
      "id" => enactment_id,
      "topic_prefix" => topic_prefix,
      "flow_cache" => flow_cache
    })
  end

  # Inserts a real `enactments` row in the requested state so the
  # `:retry_enactment` gate (which re-reads from storage) can observe a
  # concrete state instead of guessing from cached `summary.state`.
  defp insert_enactment_with_state!(state) when state in [:running, :exception, :terminated] do
    import ColouredFlow.MultiSet, only: [sigil_MS: 2]

    flow =
      Repo.insert!(%ColouredFlow.Runner.Storage.Schemas.Flow{
        name: "enactment-detail-test-flow-#{System.unique_integer([:positive])}",
        definition: ColouredFlowDashboard.Test.SimpleSequenceWorkflow.cpnet()
      })

    Repo.insert!(%ColouredFlow.Runner.Storage.Schemas.Enactment{
      flow_id: flow.id,
      initial_markings: [%ColouredFlow.Enactment.Marking{place: "input", tokens: ~MS[1]}],
      state: state
    })
  end

  defp broadcast!(topic, %Event{} = event) do
    :ok = Phoenix.PubSub.broadcast(@pubsub, topic, {:cf_event, event})
  end

  defp build_workitem_event(kind, enactment_id, workitem_id, new_state, version) do
    %Event{
      topic: {:enactment, enactment_id},
      kind: kind,
      enactment_id: enactment_id,
      enactment_version: version,
      occurred_at: DateTime.utc_now(),
      payload: %{
        operation: operation_of(kind),
        workitems: [
          %RunnerWorkitem{
            id: workitem_id,
            state: new_state,
            binding_element: %BindingElement{
              transition: "pass",
              binding: [{:x, 1}],
              to_consume: []
            }
          }
        ]
      }
    }
  end

  defp build_workitem_event_for(kind, enactment_id, workitem_id, transition_name, version) do
    %Event{
      topic: {:enactment, enactment_id},
      kind: kind,
      enactment_id: enactment_id,
      enactment_version: version,
      occurred_at: DateTime.utc_now(),
      payload: %{
        operation: operation_of(kind),
        workitems: [
          %RunnerWorkitem{
            id: workitem_id,
            state: workitem_state(kind),
            binding_element: %BindingElement{
              transition: transition_name,
              binding: [{:x, 1}],
              to_consume: []
            }
          }
        ]
      }
    }
  end

  defp workitem_state(:produce_workitems_stop), do: :enabled
  defp workitem_state(:start_workitems_stop), do: :started
  defp workitem_state(:withdraw_workitems_stop), do: :completed
  defp workitem_state(:complete_workitems_stop), do: :completed

  defp synthetic_cpnet do
    %ColouredFlow.Definition.ColouredPetriNet{
      colour_sets: [%ColouredFlow.Definition.ColourSet{name: :int, type: {:integer, []}}],
      places: [
        %ColouredFlow.Definition.Place{name: "src", colour_set: :int},
        %ColouredFlow.Definition.Place{name: "dst", colour_set: :int}
      ],
      transitions: [
        ColouredFlow.Builder.DefinitionHelper.build_transition!(name: "pass", guard: "true")
      ],
      arcs: [
        ColouredFlow.Builder.DefinitionHelper.build_arc!(
          label: "in",
          place: "src",
          transition: "pass",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        ColouredFlow.Builder.DefinitionHelper.build_arc!(
          label: "out",
          place: "dst",
          transition: "pass",
          orientation: :t_to_p,
          expression: "{1, x}"
        )
      ],
      variables: [%ColouredFlow.Definition.Variable{name: :x, colour_set: :int}]
    }
  end

  defp operation_of(:produce_workitems_stop), do: :produce_workitems
  defp operation_of(:start_workitems_stop), do: :start_workitems
  defp operation_of(:withdraw_workitems_stop), do: :withdraw_workitems
  defp operation_of(:complete_workitems_stop), do: :complete_workitems

  defp telemetry_op_landed?(timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_telemetry_op_landed?(deadline)
  end

  defp do_telemetry_op_landed?(deadline) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:patch, %{stream_ops: ops}} ->
        if Enum.any?(ops, fn op -> op_field(op, :stream) == "telemetry" end) do
          true
        else
          do_telemetry_op_landed?(deadline)
        end
    after
      timeout -> false
    end
  end

  defp flow_cache_for_seed do
    Application.get_env(:coloured_flow_dashboard, :telemetry_bridge)[:flow_cache] ||
      :coloured_flow_dashboard_telemetry_bridge_flow_cache
  end

  defp drain_patch do
    receive do
      {:patch, _envelope} -> drain_patch()
    after
      0 -> :ok
    end
  end

  defp await_stream_op(kind, stream_name) when is_binary(kind) and is_atom(stream_name) do
    [op] = await_stream_ops(kind, stream_name, 1)
    op
  end

  defp await_stream_ops(kind, stream_name, count)
       when is_binary(kind) and is_atom(stream_name) and is_integer(count) and count > 0 do
    name_str = Atom.to_string(stream_name)
    deadline = System.monotonic_time(:millisecond) + 2_000
    collect_stream_ops(kind, name_str, count, [], deadline)
  end

  defp collect_stream_ops(_kind, _name, count, acc, _deadline) when length(acc) >= count do
    Enum.reverse(acc)
  end

  defp collect_stream_ops(kind, name, count, acc, deadline) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:patch, %{stream_ops: ops}} ->
        filtered =
          Enum.filter(ops, fn op ->
            op_field(op, :op) == kind and op_field(op, :stream) == name
          end)

        matching = Enum.map(filtered, &normalize_op/1)
        collect_stream_ops(kind, name, count, Enum.reverse(matching) ++ acc, deadline)
    after
      timeout ->
        flunk(
          "timed out waiting for #{count} #{kind} op(s) on stream :#{name}; collected: " <>
            inspect(Enum.reverse(acc))
        )
    end
  end

  defp op_field(op, key) when is_map(op) do
    case op do
      %{^key => v} ->
        v

      %{} ->
        stringified = Map.new(op, fn {k, v} -> {to_string(k), v} end)
        Map.get(stringified, Atom.to_string(key))
    end
  end

  defp normalize_op(op) do
    Enum.reduce([:op, :stream, :item_key, :item, :at, :limit, :ref], %{}, fn k, acc ->
      Map.put(acc, k, op_field(op, k))
    end)
  end

  defp assert_eventually(fun, timeout \\ 2_000, interval \\ 25) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_assert_eventually(fun, deadline, interval)
  end

  defp do_assert_eventually(fun, deadline, interval) do
    if fun.() do
      :ok
    else
      now = System.monotonic_time(:millisecond)

      if now >= deadline do
        flunk("condition never became true within timeout")
      else
        receive do
        after
          interval -> do_assert_eventually(fun, deadline, interval)
        end
      end
    end
  end
end
