defmodule ColouredFlowDashboardWeb.Stores.InboxStoreTest do
  # async: false is forced by the cross-process Repo seed path: `mount/2`
  # invokes `WorkitemStream.live_query/1` from the spawned Musubi page
  # server, which needs sandbox access without per-test `Sandbox.allow/3`
  # ceremony. Bridge fan-out tests already cover the per-test isolation
  # patterns; this suite focuses on the store's event routing and
  # cursor-paged seed.
  use ColouredFlowDashboard.DataCase, async: false

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment.Workitem, as: RunnerWorkitem
  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboardWeb.Stores.InboxStore
  alias ColouredFlowDashboardWeb.Views.InboxCounts

  import ColouredFlow.MultiSet, only: [sigil_MS: 2]

  @pubsub :coloured_flow_dashboard_pubsub

  setup context do
    topic = "cf-test-#{discriminator(context)}:inbox"
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    flow_cache = String.to_atom("inbox_store_test_flow_cache_#{discriminator(context)}")
    {:ok, topic: topic, flow_cache: flow_cache}
  end

  describe "mount/2" do
    test "seeds empty state when storage has no live workitems",
         %{topic: topic, flow_cache: flow_cache} do
      page = mount_store(topic, flow_cache)

      assigns = Musubi.Testing.assigns(page)

      assert assigns.workitem_states == %{}
      assert assigns.enactment_workitems == %{}
      assert %InboxCounts{enabled: 0, started: 0, by_enactment: by_enactment} = assigns.counts
      assert by_enactment == %{}

      # `render/1` returns the runtime placeholder for the stream slot —
      # the resolver swaps it for materialised entries at envelope-build time.
      assert %{workitems: %Musubi.Stream.Placeholder{name: :workitems}} =
               Musubi.Testing.render(page)
    end

    test "seeds tracking state from `WorkitemStream.live_query/1` rows",
         %{topic: topic, flow_cache: flow_cache} do
      {:ok, enactment} = insert_enactment()
      {:ok, schema} = insert_live_workitem(enactment, :enabled, transition: "approve")

      page = mount_store(topic, flow_cache)
      assigns = Musubi.Testing.assigns(page)

      assert assigns.workitem_states == %{schema.id => :enabled}
      assert assigns.enactment_workitems == %{enactment.id => MapSet.new([schema.id])}

      assert %InboxCounts{enabled: 1, started: 0, by_enactment: by_enactment} = assigns.counts
      assert by_enactment == %{enactment.id => 1}

      # NOTE: per-cycle queued stream ops are flushed into the patch envelope
      # by `render_and_envelope` before any peek; we therefore assert on the
      # tracking state in `assigns` rather than `Musubi.Stream.pending_ops/1`.
    end
  end

  describe "event routing" do
    setup %{topic: topic, flow_cache: flow_cache} do
      page = mount_store(topic, flow_cache)
      {:ok, page: page}
    end

    test "produce_workitems_stop inserts a new live row + bumps counts",
         %{topic: topic, page: page} do
      enactment_id = Ecto.UUID.generate()
      wi_id = Ecto.UUID.generate()

      event = %Event{
        topic: :inbox,
        kind: :produce_workitems_stop,
        enactment_id: enactment_id,
        enactment_version: 1,
        occurred_at: DateTime.utc_now(),
        payload: %{
          operation: :produce_workitems,
          workitems: [
            %RunnerWorkitem{
              id: wi_id,
              state: :enabled,
              binding_element: %BindingElement{
                transition: "pass",
                binding: [{:x, 1}],
                to_consume: []
              }
            }
          ]
        }
      }

      broadcast!(topic, event)
      assigns = Musubi.Testing.assigns(page)

      assert assigns.workitem_states == %{wi_id => :enabled}
      assert assigns.enactment_workitems == %{enactment_id => MapSet.new([wi_id])}

      assert %InboxCounts{enabled: 1, started: 0, by_enactment: %{^enactment_id => 1}} =
               assigns.counts
    end

    test "start_workitems_stop upserts the row (state moves to :started)",
         %{topic: topic, page: page} do
      enactment_id = Ecto.UUID.generate()
      wi_id = Ecto.UUID.generate()

      broadcast!(topic, build_event(:produce_workitems_stop, enactment_id, wi_id, :enabled))
      broadcast!(topic, build_event(:start_workitems_stop, enactment_id, wi_id, :started))

      assigns = Musubi.Testing.assigns(page)
      assert assigns.workitem_states == %{wi_id => :started}
      assert %InboxCounts{enabled: 0, started: 1} = assigns.counts
    end

    test "complete_workitems_stop deletes the row when the new state is non-live",
         %{topic: topic, page: page} do
      enactment_id = Ecto.UUID.generate()
      wi_id = Ecto.UUID.generate()

      broadcast!(topic, build_event(:produce_workitems_stop, enactment_id, wi_id, :enabled))
      broadcast!(topic, build_event(:complete_workitems_stop, enactment_id, wi_id, :completed))

      assigns = Musubi.Testing.assigns(page)
      assert assigns.workitem_states == %{}
      assert assigns.enactment_workitems == %{}
      assert %InboxCounts{enabled: 0, started: 0, by_enactment: by_enactment} = assigns.counts
      assert by_enactment == %{}
    end

    test "withdraw_workitems_stop deletes the row",
         %{topic: topic, page: page} do
      enactment_id = Ecto.UUID.generate()
      wi_id = Ecto.UUID.generate()

      broadcast!(topic, build_event(:produce_workitems_stop, enactment_id, wi_id, :enabled))
      broadcast!(topic, build_event(:withdraw_workitems_stop, enactment_id, wi_id, :withdrawn))

      assigns = Musubi.Testing.assigns(page)
      assert assigns.workitem_states == %{}
    end

    test "enactment_terminate clears every row tracked under the enactment id",
         %{topic: topic, page: page} do
      enactment_id = Ecto.UUID.generate()
      wi_a = Ecto.UUID.generate()
      wi_b = Ecto.UUID.generate()
      other_enactment = Ecto.UUID.generate()
      wi_other = Ecto.UUID.generate()

      broadcast!(topic, build_event(:produce_workitems_stop, enactment_id, wi_a, :enabled))
      broadcast!(topic, build_event(:produce_workitems_stop, enactment_id, wi_b, :enabled))
      broadcast!(topic, build_event(:produce_workitems_stop, other_enactment, wi_other, :enabled))

      terminate_event = %Event{
        topic: :inbox,
        kind: :enactment_terminate,
        enactment_id: enactment_id,
        enactment_version: 3,
        occurred_at: DateTime.utc_now(),
        payload: %{termination_type: :force, termination_message: nil}
      }

      broadcast!(topic, terminate_event)

      assigns = Musubi.Testing.assigns(page)
      assert assigns.workitem_states == %{wi_other => :enabled}
      assert assigns.enactment_workitems == %{other_enactment => MapSet.new([wi_other])}
      assert %InboxCounts{enabled: 1, started: 0, by_enactment: by_enactment} = assigns.counts
      assert by_enactment == %{other_enactment => 1}
    end

    test "ignores unrelated event kinds without crashing the page server",
         %{topic: topic, page: page} do
      for kind <- [
            :enactment_start,
            :enactment_stop,
            :enactment_exception,
            :enactment_take_snapshot,
            :produce_workitems_start,
            :produce_workitems_exception,
            :start_workitems_start,
            :start_workitems_exception,
            :withdraw_workitems_start,
            :withdraw_workitems_exception,
            :complete_workitems_start,
            :complete_workitems_exception
          ] do
        event = %Event{
          topic: :inbox,
          kind: kind,
          enactment_id: Ecto.UUID.generate(),
          enactment_version: 0,
          occurred_at: DateTime.utc_now(),
          payload: %{}
        }

        broadcast!(topic, event)
      end

      assigns = Musubi.Testing.assigns(page)
      assert assigns.workitem_states == %{}
      assert %InboxCounts{enabled: 0, started: 0} = assigns.counts
    end

    test "non-cf mailbox traffic is dropped without affecting state",
         %{topic: _topic, page: page} do
      send(page.pid, :random_noise)
      send(page.pid, {:something_else, "ok"})

      assigns = Musubi.Testing.assigns(page)
      assert assigns.workitem_states == %{}
      assert %InboxCounts{enabled: 0, started: 0} = assigns.counts
    end
  end

  describe "integration with a real runner + InMemory storage" do
    test "consumes bridge fan-out from a live runner firing", %{
      topic: _topic,
      flow_cache: flow_cache
    } do
      # Mount the store directly against the application's `cf:inbox` topic
      # so the global TelemetryBridge's fan-out reaches it without a relay.
      # We are `async: false`, so the suite already serializes; the global
      # topic is safe to share here.
      page =
        Musubi.Testing.mount(InboxStore, %{
          "topic" => "cf:inbox",
          "flow_cache" => flow_cache
        })

      require ColouredFlow.Runner.Storage.InMemory, as: InMemory
      alias ColouredFlowDashboard.Test.SimpleSequenceWorkflow

      flow = InMemory.insert_flow!(SimpleSequenceWorkflow.cpnet())
      flow_id = InMemory.flow(flow, :id)
      {:ok, enactment} = SimpleSequenceWorkflow.insert_enactment(flow_id)
      enactment_id = InMemory.enactment(enactment, :id)

      {:ok, _pid} =
        SimpleSequenceWorkflow.start_enactment(enactment_id, lifecycle_hooks: nil)

      assert_eventually(fn ->
        case Musubi.Testing.assigns(page) do
          %{enactment_workitems: map} when is_map_key(map, enactment_id) ->
            MapSet.size(map[enactment_id]) > 0

          _other ->
            false
        end
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp discriminator(context),
    do: Integer.to_string(:erlang.phash2({context.module, context.test}))

  defp mount_store(topic, flow_cache) do
    Musubi.Testing.mount(InboxStore, %{
      "topic" => topic,
      "flow_cache" => flow_cache
    })
  end

  defp broadcast!(topic, %Event{} = event) do
    :ok = Phoenix.PubSub.broadcast(@pubsub, topic, {:cf_event, event})
  end

  defp build_event(kind, enactment_id, workitem_id, new_state) do
    %Event{
      topic: :inbox,
      kind: kind,
      enactment_id: enactment_id,
      enactment_version: 1,
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

  defp insert_enactment do
    flow =
      Repo.insert!(%Schemas.Flow{
        name: "inbox-store-test-flow-#{System.unique_integer([:positive])}",
        definition: ColouredFlowDashboard.Test.SimpleSequenceWorkflow.cpnet()
      })

    Repo.insert(%Schemas.Enactment{
      flow_id: flow.id,
      initial_markings: [%Marking{place: "input", tokens: ~MS[1]}],
      state: :running
    })
  end

  defp insert_live_workitem(enactment, state, opts) do
    transition = Keyword.get(opts, :transition, "pass")

    Repo.insert(%Schemas.Workitem{
      enactment_id: enactment.id,
      state: state,
      binding_element: %BindingElement{
        transition: transition,
        binding: [{:x, 1}],
        to_consume: []
      }
    })
  end

  # Spins until `fun.()` returns truthy or the deadline elapses. The
  # waiter is built around `receive after` rather than `Process.sleep/1`
  # (repo rule: never sleep in tests) so the BEAM scheduler is free to
  # advance other processes between checks.
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
