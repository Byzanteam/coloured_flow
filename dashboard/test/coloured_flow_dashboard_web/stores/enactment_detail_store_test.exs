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

  defp operation_of(:produce_workitems_stop), do: :produce_workitems
  defp operation_of(:start_workitems_stop), do: :start_workitems
  defp operation_of(:withdraw_workitems_stop), do: :withdraw_workitems
  defp operation_of(:complete_workitems_stop), do: :complete_workitems

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
