defmodule ColouredFlowDashboard.TelemetryBridgeTest do
  # async: true is safe because every test spins up its OWN TelemetryBridge
  # instance with a unique handler_id, unique flow-cache table, and a
  # unique PubSub topic prefix. The app's global bridge is also attached
  # (it boots with the dashboard application), but it broadcasts to the
  # default "cf:" prefix which no test subscribes to. See `start_bridge/2`.
  use ExUnit.Case, async: true

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment, as: RunnerEnactment
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlowDashboard.TelemetryBridge
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboard.Test.SimpleSequenceWorkflow

  import ColouredFlow.MultiSet, only: [sigil_MS: 2]

  require ColouredFlow.Runner.Storage.InMemory, as: InMemory

  @pubsub :coloured_flow_dashboard_pubsub
  @task_supervisor ColouredFlowDashboard.TaskSupervisor

  defp unique_token, do: Integer.to_string(System.unique_integer([:positive, :monotonic]))

  defp build_state(enactment_id, overrides \\ []) do
    base = %RunnerEnactment{
      enactment_id: enactment_id,
      version: 3,
      markings: %{
        "input" => %Marking{place: "input", tokens: ~MS[1 1 2]},
        "output" => %Marking{place: "output", tokens: ~MS[]}
      },
      workitems: %{
        "wi-1" => %Workitem{
          id: "wi-1",
          state: :enabled,
          binding_element: %ColouredFlow.Enactment.BindingElement{
            transition: "pass",
            binding: [{:x, 1}],
            to_consume: []
          }
        }
      }
    }

    struct!(base, overrides)
  end

  defp unique_id(suffix),
    do: "enactment-#{System.unique_integer([:positive, :monotonic])}#{suffix}"

  # Starts a per-test bridge isolated from the global one: unique handler id,
  # unique ETS flow cache, unique topic prefix. Returns the prefix + handler
  # config so tests can subscribe + drive the bridge.
  defp start_bridge(context, opts \\ []) do
    token = unique_token()
    prefix = "cf-#{context.test_token}-#{token}:"
    handler_id = {context.module, context.test, token}
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    flow_cache = String.to_atom("#{context.module}.FlowCache.#{context.test_token}.#{token}")
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    bridge_name = String.to_atom("#{context.module}.Bridge.#{context.test_token}.#{token}")

    bridge_opts =
      [
        name: bridge_name,
        handler_id: handler_id,
        pubsub: @pubsub,
        task_supervisor: @task_supervisor,
        topic_prefix: prefix,
        flow_cache: flow_cache
      ] ++ opts

    # Explicit `:id` so multiple bridges with different names can coexist
    # under the test supervisor (default child_id is the module atom, which
    # collides across `start_bridge/2` calls in the same test).
    spec = Supervisor.child_spec({TelemetryBridge, bridge_opts}, id: bridge_name)
    pid = start_supervised!(spec)

    %{prefix: prefix, handler_id: handler_id, flow_cache: flow_cache, bridge: pid}
  end

  defp subscribe_topics(prefix, enactment_id) do
    :ok = Phoenix.PubSub.subscribe(@pubsub, "#{prefix}inbox")
    :ok = Phoenix.PubSub.subscribe(@pubsub, "#{prefix}enactment:#{enactment_id}")
  end

  setup context do
    # Stable per-test discriminator the helpers can interpolate into atoms
    # and topic strings without ever collapsing across tests.
    token = Integer.to_string(:erlang.phash2({context.module, context.test}))
    {:ok, %{test_token: token}}
  end

  describe "events/0 catalog" do
    test "matches the full set in ColouredFlow.Runner.Telemetry.DefaultLogger" do
      lifecycles =
        for ev <- [:start, :stop, :terminate, :exception, :take_snapshot],
            do: [:coloured_flow, :runner, :enactment, ev]

      workitem_ops =
        for op <- [
              :produce_workitems,
              :start_workitems,
              :withdraw_workitems,
              :complete_workitems
            ],
            ev <- [:start, :stop, :exception],
            do: [:coloured_flow, :runner, :enactment, op, ev]

      expected = lifecycles ++ workitem_ops

      assert MapSet.new(TelemetryBridge.events()) == MapSet.new(expected)
    end

    test "Event.kinds/0 covers every emitted kind for every event in events/0" do
      kinds = MapSet.new(Event.kinds())

      for event <- TelemetryBridge.events() do
        kind =
          case event do
            [:coloured_flow, :runner, :enactment, lifecycle] ->
              String.to_existing_atom("enactment_#{lifecycle}")

            [:coloured_flow, :runner, :enactment, op, ev] ->
              String.to_existing_atom("#{op}_#{ev}")
          end

        assert kind in kinds, "missing kind #{inspect(kind)} for event #{inspect(event)}"
      end
    end
  end

  describe "broadcast fan-out" do
    setup context, do: start_bridge(context)

    test "enactment :start fans out to inbox and enactment topics", %{
      prefix: prefix,
      handler_id: handler_id
    } do
      eid = unique_id("-start")
      subscribe_topics(prefix, eid)
      state = build_state(eid)

      execute_via_handler(
        handler_id,
        [:coloured_flow, :runner, :enactment, :start],
        %{system_time: System.system_time()},
        %{enactment_id: eid, enactment_state: state}
      )

      assert_receive {:cf_event, %Event{kind: :enactment_start, topic: :inbox} = inbox_event},
                     1_000

      assert_receive {:cf_event,
                      %Event{kind: :enactment_start, topic: {:enactment, ^eid}} = scoped_event},
                     1_000

      assert inbox_event.enactment_id == eid
      assert inbox_event.enactment_version == 3
      assert %DateTime{} = inbox_event.occurred_at
      assert inbox_event.markings_summary.total_tokens == 3
      assert inbox_event.markings_summary.place_count == 2
      assert inbox_event.workitems_summary.count == 1
      assert inbox_event.workitems_summary.by_state == %{enabled: 1}
      assert scoped_event.payload == %{}
    end

    test "enactment :exception carries reason and formatted error banner",
         %{prefix: prefix, handler_id: handler_id} do
      eid = unique_id("-exc")
      subscribe_topics(prefix, eid)
      state = build_state(eid)

      execute_via_handler(
        handler_id,
        [:coloured_flow, :runner, :enactment, :exception],
        %{system_time: System.system_time()},
        %{
          enactment_id: eid,
          enactment_state: state,
          exception_reason: :snapshot_corrupt,
          exception: %RuntimeError{message: "snapshot row was corrupt"}
        }
      )

      assert_receive {:cf_event, %Event{kind: :enactment_exception, topic: :inbox} = event},
                     1_000

      assert event.payload.exception_reason == :snapshot_corrupt
      assert event.payload.error_banner =~ "snapshot row was corrupt"
    end

    test "produce_workitems :start carries binding_elements list",
         %{prefix: prefix, handler_id: handler_id} do
      eid = unique_id("-produce")
      subscribe_topics(prefix, eid)
      state = build_state(eid)

      binding_element = %ColouredFlow.Enactment.BindingElement{
        transition: "pass",
        binding: [{:x, 1}],
        to_consume: []
      }

      execute_via_handler(
        handler_id,
        [:coloured_flow, :runner, :enactment, :produce_workitems, :start],
        %{system_time: System.system_time()},
        %{
          enactment_id: eid,
          enactment_state: state,
          binding_elements: [binding_element]
        }
      )

      assert_receive {:cf_event, %Event{kind: :produce_workitems_start, topic: :inbox} = event},
                     1_000

      assert event.payload.operation == :produce_workitems
      assert event.payload.binding_elements == [binding_element]
    end

    test "complete_workitems :start carries workitem_ids and output map",
         %{prefix: prefix, handler_id: handler_id} do
      eid = unique_id("-complete")
      subscribe_topics(prefix, eid)
      state = build_state(eid)
      outputs = [{"wi-1", [x: 1]}, {"wi-2", [x: 2]}]

      execute_via_handler(
        handler_id,
        [:coloured_flow, :runner, :enactment, :complete_workitems, :start],
        %{system_time: System.system_time()},
        %{
          enactment_id: eid,
          enactment_state: state,
          workitem_ids: ["wi-1", "wi-2"],
          workitem_id_and_outputs: outputs
        }
      )

      assert_receive {:cf_event, %Event{kind: :complete_workitems_start, topic: :inbox} = event},
                     1_000

      assert event.payload.workitem_ids == ["wi-1", "wi-2"]
      assert event.payload.workitem_id_and_outputs == Map.new(outputs)
    end

    test "operation :stop carries workitems list",
         %{prefix: prefix, handler_id: handler_id} do
      eid = unique_id("-stop")
      subscribe_topics(prefix, eid)
      state = build_state(eid)

      workitems = [
        %Workitem{
          id: "wi-1",
          state: :started,
          binding_element: %ColouredFlow.Enactment.BindingElement{
            transition: "pass",
            binding: [{:x, 1}],
            to_consume: []
          }
        }
      ]

      execute_via_handler(
        handler_id,
        [:coloured_flow, :runner, :enactment, :start_workitems, :stop],
        %{system_time: System.system_time(), duration: 12_345},
        %{enactment_id: eid, enactment_state: state, workitems: workitems}
      )

      assert_receive {:cf_event, %Event{kind: :start_workitems_stop, topic: :inbox} = event},
                     1_000

      assert event.payload.operation == :start_workitems
      assert event.payload.workitems == workitems
    end

    test "operation :exception derives an error banner from kind/reason/stacktrace",
         %{prefix: prefix, handler_id: handler_id} do
      eid = unique_id("-op-exc")
      subscribe_topics(prefix, eid)
      state = build_state(eid)

      execute_via_handler(
        handler_id,
        [:coloured_flow, :runner, :enactment, :produce_workitems, :exception],
        %{system_time: System.system_time(), duration: 99},
        %{
          enactment_id: eid,
          enactment_state: state,
          kind: :error,
          reason: %RuntimeError{message: "boom"},
          stacktrace: []
        }
      )

      assert_receive {:cf_event, %Event{kind: :produce_workitems_exception} = event}, 1_000

      assert event.payload.operation == :produce_workitems
      assert event.payload.kind == :error
      assert event.payload.error_banner =~ "boom"
    end
  end

  describe "robustness" do
    setup context, do: start_bridge(context)

    test "drops events whose metadata lacks :enactment_state",
         %{prefix: prefix, handler_id: handler_id} do
      eid = unique_id("-missing-state")
      subscribe_topics(prefix, eid)

      execute_via_handler(
        handler_id,
        [:coloured_flow, :runner, :enactment, :start],
        %{system_time: System.system_time()},
        %{enactment_id: eid}
      )

      refute_receive {:cf_event, _}, 200
    end
  end

  describe "topic isolation" do
    test "parallel bridges on different prefixes do not cross-pollute", context do
      %{prefix: prefix_a, handler_id: handler_a} = start_bridge(context)
      %{prefix: prefix_b, handler_id: handler_b} = start_bridge(context)

      eid = unique_id("-cross")
      state = build_state(eid)

      :ok = Phoenix.PubSub.subscribe(@pubsub, "#{prefix_a}inbox")
      :ok = Phoenix.PubSub.subscribe(@pubsub, "#{prefix_b}inbox")

      # Drive bridge A only — invoke its specific handler so bridge B does
      # not receive this synthetic event. (`:telemetry.execute/3` would
      # fire BOTH handlers; this test pins isolation at the topic layer.)
      execute_via_handler(
        handler_a,
        [:coloured_flow, :runner, :enactment, :start],
        %{system_time: System.system_time()},
        %{enactment_id: eid, enactment_state: state}
      )

      assert_receive {:cf_event, %Event{kind: :enactment_start, topic: :inbox}}, 1_000

      # Bridge B subscribed to its own topic; the message above landed on
      # bridge A's prefix only. Drive B and check it sees ITS event.
      execute_via_handler(
        handler_b,
        [:coloured_flow, :runner, :enactment, :start],
        %{system_time: System.system_time()},
        %{enactment_id: eid, enactment_state: state}
      )

      # A's mailbox now holds exactly ONE more message — the one we just
      # broadcast via B on prefix_b. We dequeue both; both arrived once.
      messages = drain_cf_events()
      assert length(messages) == 1, "expected single second-event, got #{inspect(messages)}"
    end
  end

  describe "async invariant — broadcast_fn indirection" do
    test "handle_event returns BEFORE the broadcast lands", context do
      test_pid = self()

      # Block the first broadcast only — subsequent broadcasts in the same
      # task process fall through so the test doesn't deadlock when the
      # bridge fans out two topics (inbox + enactment) for one event.
      blocker = fn pubsub, topic, msg ->
        case Process.get(:cf_blocked?) do
          true ->
            Phoenix.PubSub.broadcast(pubsub, topic, msg)

          _missing ->
            Process.put(:cf_blocked?, true)
            send(test_pid, {:broadcast_blocked, self(), topic})

            receive do
              :release -> Phoenix.PubSub.broadcast(pubsub, topic, msg)
            after
              5_000 -> :timeout
            end
        end
      end

      %{prefix: prefix, handler_id: handler_id} =
        start_bridge(context, broadcast_fn: blocker)

      eid = unique_id("-async")
      :ok = Phoenix.PubSub.subscribe(@pubsub, "#{prefix}inbox")
      state = build_state(eid)

      execute_via_handler(
        handler_id,
        [:coloured_flow, :runner, :enactment, :start],
        %{system_time: System.system_time()},
        %{enactment_id: eid, enactment_state: state}
      )

      # If `handle_event` ever calls broadcast synchronously, the blocker
      # would run inside the test process, send-to-self, then block on
      # `receive :release` — which never arrives — and `execute_via_handler`
      # would never return. We made it past that call.

      # The broadcast task must be parked inside the blocker.
      assert_receive {:broadcast_blocked, broadcast_pid, topic}, 1_000
      assert topic == "#{prefix}inbox" or topic =~ "#{prefix}enactment:"

      # Mailbox must NOT yet contain the broadcast — the blocker has not
      # released. This is the deterministic ordering check.
      refute_received {:cf_event, _}

      send(broadcast_pid, :release)
      assert_receive {:cf_event, %Event{kind: :enactment_start}}, 1_000
    end
  end

  describe "integration smoke (real runner + InMemory storage)" do
    test "drives a tiny pass-through CPN and observes the lifecycle stream including cf:flow",
         context do
      %{prefix: prefix} = start_bridge(context)

      flow = InMemory.insert_flow!(SimpleSequenceWorkflow.cpnet())
      flow_id = InMemory.flow(flow, :id)

      {:ok, enactment} = SimpleSequenceWorkflow.insert_enactment(flow_id)
      enactment_id = runner_enactment_id(enactment)
      flow_topic = TelemetryBridge.flow_topic_id(SimpleSequenceWorkflow.cpnet())

      subscribe_topics(prefix, enactment_id)
      :ok = Phoenix.PubSub.subscribe(@pubsub, "#{prefix}flow:#{flow_topic}")

      {:ok, _pid} =
        SimpleSequenceWorkflow.start_enactment(enactment_id, lifecycle_hooks: nil)

      # Inbox + enactment topics
      assert_receive {:cf_event,
                      %Event{
                        kind: :enactment_start,
                        topic: :inbox,
                        enactment_id: ^enactment_id
                      }},
                     2_000

      assert_receive {:cf_event,
                      %Event{
                        kind: :produce_workitems_start,
                        topic: :inbox,
                        enactment_id: ^enactment_id
                      } = produce_start},
                     2_000

      assert length(produce_start.payload.binding_elements) == 1

      assert_receive {:cf_event,
                      %Event{
                        kind: :produce_workitems_stop,
                        topic: :inbox,
                        enactment_id: ^enactment_id
                      }},
                     2_000

      assert_receive {:cf_event,
                      %Event{
                        kind: :produce_workitems_stop,
                        topic: {:enactment, ^enactment_id}
                      }},
                     2_000

      # cf:flow:<id> closes the third-topic requirement
      assert_receive {:cf_event,
                      %Event{
                        kind: :enactment_start,
                        topic: {:flow, ^flow_topic},
                        enactment_id: ^enactment_id
                      }},
                     2_000

      assert_receive {:cf_event,
                      %Event{
                        kind: :produce_workitems_stop,
                        topic: {:flow, ^flow_topic},
                        enactment_id: ^enactment_id
                      }},
                     2_000
    end
  end

  # Routes a synthetic event through ONLY the bridge identified by
  # `handler_id`. Tests use this instead of `:telemetry.execute/3` so a
  # given test sees only its own bridge's broadcasts — `:telemetry.execute`
  # would fan out to the app's global bridge AND every per-test bridge
  # attached at the time, breaking async isolation.
  defp execute_via_handler(handler_id, event_name, measurements, metadata) do
    handler =
      event_name
      |> :telemetry.list_handlers()
      |> Enum.find(&(&1.id == handler_id))

    handler.function.(event_name, measurements, metadata, handler.config)
  end

  defp drain_cf_events(acc \\ []) do
    receive do
      {:cf_event, _event} = msg -> drain_cf_events([msg | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end

  defp runner_enactment_id(record) when is_tuple(record) and elem(record, 0) == :enactment,
    do: InMemory.enactment(record, :id)

  defp runner_enactment_id(%{id: id}) when is_binary(id), do: id
end
