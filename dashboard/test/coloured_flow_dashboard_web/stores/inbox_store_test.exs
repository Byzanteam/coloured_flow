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

    test "enactment_exception flips enactment_states + restamps tracked rows",
         %{topic: topic, page: page} do
      enactment_id = Ecto.UUID.generate()
      wi_id = Ecto.UUID.generate()

      broadcast!(topic, build_event(:produce_workitems_stop, enactment_id, wi_id, :enabled))
      broadcast!(topic, build_lifecycle_event(:enactment_exception, enactment_id))

      assigns = Musubi.Testing.assigns(page)
      assert assigns.enactment_states == %{enactment_id => :exception}

      row = Map.fetch!(assigns.workitem_rows, wi_id)
      assert row.enactment_state == :exception
    end

    test "enactment_start flips enactment_states back to :running + restamps",
         %{topic: topic, page: page} do
      enactment_id = Ecto.UUID.generate()
      wi_id = Ecto.UUID.generate()

      broadcast!(topic, build_event(:produce_workitems_stop, enactment_id, wi_id, :enabled))
      broadcast!(topic, build_lifecycle_event(:enactment_exception, enactment_id))
      broadcast!(topic, build_lifecycle_event(:enactment_start, enactment_id))

      assigns = Musubi.Testing.assigns(page)
      assert assigns.enactment_states == %{enactment_id => :running}

      row = Map.fetch!(assigns.workitem_rows, wi_id)
      assert row.enactment_state == :running
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

  describe "stream wire ops (regression: item_key insert/delete symmetry)" do
    # Codex P8 BLOCKING: with the Musubi-default stream item_key
    # (`"workitems-#{id}"`) and a delete site that passed the bare UUID,
    # `stream_delete_by_item_key/3` never matched the inserted row and the
    # client kept stale rows across `:complete / :withdraw / :terminate`.
    # The store now declares `item_key: &(&1.id)`; this suite locks the
    # insert+delete key shapes into one shape via the actual patch envelope.
    setup %{topic: topic, flow_cache: flow_cache} do
      # Drain the mount envelope (initial wire-root replace) so the per-test
      # assertions only see envelopes triggered by `broadcast!/2` events.
      page = mount_store(topic, flow_cache)
      _drained = drain_patch()
      {:ok, page: page}
    end

    test "produce → complete: delete carries the same item_key as the insert",
         %{topic: topic, page: _page} do
      enactment_id = Ecto.UUID.generate()
      wi_id = Ecto.UUID.generate()

      broadcast!(topic, build_event(:produce_workitems_stop, enactment_id, wi_id, :enabled))
      assert %{op: "insert", item_key: insert_key} = await_stream_op("insert", :workitems)
      assert insert_key == wi_id

      broadcast!(topic, build_event(:complete_workitems_stop, enactment_id, wi_id, :completed))
      assert %{op: "delete", item_key: delete_key} = await_stream_op("delete", :workitems)
      assert delete_key == insert_key
    end

    test "produce → withdraw: delete carries the same item_key as the insert",
         %{topic: topic, page: _page} do
      enactment_id = Ecto.UUID.generate()
      wi_id = Ecto.UUID.generate()

      broadcast!(topic, build_event(:produce_workitems_stop, enactment_id, wi_id, :enabled))
      assert %{op: "insert", item_key: insert_key} = await_stream_op("insert", :workitems)

      broadcast!(topic, build_event(:withdraw_workitems_stop, enactment_id, wi_id, :withdrawn))
      assert %{op: "delete", item_key: delete_key} = await_stream_op("delete", :workitems)
      assert delete_key == insert_key
    end

    test "enactment_terminate emits a delete op per tracked row, all keyed by id",
         %{topic: topic, page: _page} do
      enactment_id = Ecto.UUID.generate()
      wi_a = Ecto.UUID.generate()
      wi_b = Ecto.UUID.generate()

      broadcast!(topic, build_event(:produce_workitems_stop, enactment_id, wi_a, :enabled))
      assert %{item_key: ^wi_a} = await_stream_op("insert", :workitems)

      broadcast!(topic, build_event(:produce_workitems_stop, enactment_id, wi_b, :enabled))
      assert %{item_key: ^wi_b} = await_stream_op("insert", :workitems)

      terminate_event = %Event{
        topic: :inbox,
        kind: :enactment_terminate,
        enactment_id: enactment_id,
        enactment_version: 3,
        occurred_at: DateTime.utc_now(),
        payload: %{termination_type: :force, termination_message: nil}
      }

      broadcast!(topic, terminate_event)
      delete_ops = await_stream_ops("delete", :workitems, 2)
      assert Enum.sort(Enum.map(delete_ops, & &1.item_key)) == Enum.sort([wi_a, wi_b])
    end
  end

  describe "flow_topic_id cache miss (regression: undefined ETS table)" do
    # Codex P8 MINOR: when the bridge's flow_cache ETS table does not exist
    # (bridge not running, table renamed, isolated test cache) the row must
    # still be inserted with `flow_topic_id: nil` — never dropped.
    test "row is streamed with flow_topic_id: nil when cache table is undefined",
         %{topic: topic} do
      # An atom that is never created as an ETS table: `:ets.whereis/1`
      # returns `:undefined`, hitting the `resolve_flow_topic_id` miss path.
      missing_cache = unique_cache_atom("inbox_store_cache_miss_")

      assert :ets.whereis(missing_cache) == :undefined

      page = mount_store(topic, missing_cache)
      _drained = drain_patch()

      enactment_id = Ecto.UUID.generate()
      wi_id = Ecto.UUID.generate()
      broadcast!(topic, build_event(:produce_workitems_stop, enactment_id, wi_id, :enabled))

      insert = await_stream_op("insert", :workitems)
      assert insert.item_key == wi_id
      # The streamed item is wire-encoded (string keys) — see `Wire.to_wire/1`.
      assert is_nil(insert.item["flow_topic_id"])
      assert insert.item["id"] == wi_id

      assigns = Musubi.Testing.assigns(page)
      assert assigns.workitem_states == %{wi_id => :enabled}
      assert assigns.enactment_workitems == %{enactment_id => MapSet.new([wi_id])}
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

  describe ":complete_workitem command" do
    # `:complete_workitem` rides the InMemory runner end-to-end so the
    # command verifies against the real `WorkitemTransition.complete_workitem`
    # surface (state machine + occurrence emission), not a mock.
    require ColouredFlow.Runner.Storage.InMemory, as: InMemory
    alias ColouredFlowDashboard.Test.SimpleSequenceWorkflow

    setup %{flow_cache: flow_cache} do
      page =
        Musubi.Testing.mount(InboxStore, %{
          "topic" => "cf:inbox",
          "flow_cache" => flow_cache
        })

      flow = InMemory.insert_flow!(SimpleSequenceWorkflow.cpnet())
      flow_id = InMemory.flow(flow, :id)
      {:ok, enactment} = SimpleSequenceWorkflow.insert_enactment(flow_id)
      enactment_id = InMemory.enactment(enactment, :id)

      {:ok, _pid} = SimpleSequenceWorkflow.start_enactment(enactment_id, lifecycle_hooks: nil)

      workitem_id =
        assert_eventually_workitem_id(page, enactment_id)

      {:ok, page: page, enactment_id: enactment_id, workitem_id: workitem_id}
    end

    test "happy path: ok reply + stream removed", %{
      page: page,
      enactment_id: enactment_id,
      workitem_id: workitem_id
    } do
      assert {:ok, %{code: :ok}} =
               Musubi.Testing.dispatch_command(page, :complete_workitem, %{
                 workitem_id: workitem_id,
                 outputs: %{}
               })

      assert_eventually(fn ->
        case Musubi.Testing.assigns(page) do
          %{enactment_workitems: map} -> not is_map_key(map, enactment_id)
          _other -> false
        end
      end)
    end

    test "second completion returns :already_completed", %{
      page: page,
      workitem_id: workitem_id
    } do
      assert {:ok, %{code: :ok}} =
               Musubi.Testing.dispatch_command(page, :complete_workitem, %{
                 workitem_id: workitem_id,
                 outputs: %{}
               })

      # First completion drops the row from `workitem_meta`, so the second
      # dispatch lands in the `:unknown_workitem` branch. That is the
      # observable already-completed signal from a client's perspective.
      assert {:ok, %{code: code}} =
               Musubi.Testing.dispatch_command(page, :complete_workitem, %{
                 workitem_id: workitem_id,
                 outputs: %{}
               })

      assert code in [:already_completed, :unknown_workitem]
    end

    test "unknown_variable when outputs key has no existing atom", %{
      page: page,
      workitem_id: workitem_id
    } do
      garbage = "cf_inbox_test_no_such_atom_#{System.unique_integer([:positive])}"

      assert {:ok, %{code: :unknown_variable, variable: ^garbage}} =
               Musubi.Testing.dispatch_command(page, :complete_workitem, %{
                 workitem_id: workitem_id,
                 outputs: %{garbage => "ignored"}
               })
    end

    test "invalid_outputs when outputs is not a map", %{
      page: page,
      workitem_id: workitem_id
    } do
      # Wire layer normalizes scalar payload values, so a string outputs
      # value reaches `handle_command/3` as a string and trips the guard.
      assert {:ok, %{code: :invalid_outputs}} =
               Musubi.Testing.dispatch_command(page, :complete_workitem, %{
                 workitem_id: workitem_id,
                 outputs: "not a map"
               })
    end

    test "unknown_workitem when id is not tracked", %{page: page} do
      bogus = Ecto.UUID.generate()

      assert {:ok, %{code: :unknown_workitem, workitem_id: ^bogus}} =
               Musubi.Testing.dispatch_command(page, :complete_workitem, %{
                 workitem_id: bogus,
                 outputs: %{}
               })
    end

    defp assert_eventually_workitem_id(page, enactment_id) do
      assert_eventually(fn ->
        case Musubi.Testing.assigns(page) do
          %{enactment_workitems: %{^enactment_id => ids}} ->
            MapSet.size(ids) > 0

          _other ->
            false
        end
      end)

      %{enactment_workitems: %{^enactment_id => ids}} = Musubi.Testing.assigns(page)
      ids |> MapSet.to_list() |> List.first()
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

  defp build_lifecycle_event(kind, enactment_id) do
    %Event{
      topic: :inbox,
      kind: kind,
      enactment_id: enactment_id,
      enactment_version: 1,
      occurred_at: DateTime.utc_now(),
      payload: %{}
    }
  end

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

  # Builds a fresh atom for a per-test ETS cache name. The atom is created
  # at runtime — `String.to_existing_atom/1` would fail since this exact
  # value has never been encountered before. The credo override is scoped
  # narrowly to this one call site.
  defp unique_cache_atom(prefix) when is_binary(prefix) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    String.to_atom(prefix <> Integer.to_string(System.unique_integer([:positive])))
  end

  # Drains any pending patch envelopes addressed to the test process; used
  # in `setup` to discard the initial mount envelope before per-test
  # assertions on stream ops.
  defp drain_patch do
    receive do
      {:patch, _envelope} -> drain_patch()
    after
      0 -> :ok
    end
  end

  # Waits for one matching stream op from the next patch envelope; the
  # page server emits a fresh envelope per `handle_info/2` cycle, so each
  # broadcast we make is observable as exactly one `{:patch, _}` message.
  defp await_stream_op(kind, stream_name) when is_binary(kind) and is_atom(stream_name) do
    case await_stream_ops(kind, stream_name, 1) do
      [op] -> op
    end
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
