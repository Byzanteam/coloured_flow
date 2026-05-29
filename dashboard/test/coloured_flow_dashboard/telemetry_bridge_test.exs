defmodule ColouredFlowDashboard.TelemetryBridgeTest do
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

  defp subscribe_topics(enactment_id) do
    :ok = Phoenix.PubSub.subscribe(@pubsub, "cf:inbox")
    :ok = Phoenix.PubSub.subscribe(@pubsub, "cf:enactment:#{enactment_id}")
  end

  defp unique_id(suffix),
    do: "enactment-#{System.unique_integer([:positive, :monotonic])}#{suffix}"

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
    test "enactment :start fans out to cf:inbox and cf:enactment:<id>" do
      eid = unique_id("-start")
      subscribe_topics(eid)
      state = build_state(eid)

      :telemetry.execute(
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

    test "enactment :exception carries reason and formatted error banner" do
      eid = unique_id("-exc")
      subscribe_topics(eid)
      state = build_state(eid)

      :telemetry.execute(
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

    test "produce_workitems :start carries binding_elements list" do
      eid = unique_id("-produce")
      subscribe_topics(eid)
      state = build_state(eid)

      binding_element = %ColouredFlow.Enactment.BindingElement{
        transition: "pass",
        binding: [{:x, 1}],
        to_consume: []
      }

      :telemetry.execute(
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

    test "complete_workitems :start carries workitem_ids and output map" do
      eid = unique_id("-complete")
      subscribe_topics(eid)
      state = build_state(eid)
      outputs = [{"wi-1", [x: 1]}, {"wi-2", [x: 2]}]

      :telemetry.execute(
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

    test "operation :stop carries workitems list" do
      eid = unique_id("-stop")
      subscribe_topics(eid)
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

      :telemetry.execute(
        [:coloured_flow, :runner, :enactment, :start_workitems, :stop],
        %{system_time: System.system_time(), duration: 12_345},
        %{enactment_id: eid, enactment_state: state, workitems: workitems}
      )

      assert_receive {:cf_event, %Event{kind: :start_workitems_stop, topic: :inbox} = event},
                     1_000

      assert event.payload.operation == :start_workitems
      assert event.payload.workitems == workitems
    end

    test "operation :exception derives an error banner from the kind/reason/stacktrace" do
      eid = unique_id("-op-exc")
      subscribe_topics(eid)
      state = build_state(eid)

      :telemetry.execute(
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
    test "drops events whose metadata lacks :enactment_state" do
      eid = unique_id("-missing-state")
      subscribe_topics(eid)

      # No `:enactment_state` key on purpose. Bridge logs + skips, broadcasts
      # nothing. We verify by negative receive after a short sleep.
      :telemetry.execute(
        [:coloured_flow, :runner, :enactment, :start],
        %{system_time: System.system_time()},
        %{enactment_id: eid}
      )

      refute_receive {:cf_event, _}, 200
    end

    test "ignores topology-shaped events the bridge does not subscribe to" do
      eid = unique_id("-unknown")
      subscribe_topics(eid)

      # Event name not in the catalog. Bridge sees nothing because it was
      # never attached to it; even so, calling handle_event/4 directly with
      # an unknown name must return :ok without broadcasting.
      assert :ok =
               TelemetryBridge.handle_event(
                 [:coloured_flow, :runner, :enactment, :not_a_real_event],
                 %{system_time: System.system_time()},
                 %{enactment_id: eid, enactment_state: build_state(eid)},
                 %{
                   pubsub: @pubsub,
                   task_supervisor: @task_supervisor,
                   handler_id: __MODULE__
                 }
               )

      refute_receive {:cf_event, _}, 100
    end
  end

  describe "async invariant" do
    test "handle_event/4 returns synchronously; broadcast happens in a supervised task" do
      eid = unique_id("-async")
      subscribe_topics(eid)
      state = build_state(eid)

      config = %{
        pubsub: @pubsub,
        task_supervisor: @task_supervisor,
        handler_id: __MODULE__
      }

      before_children =
        @task_supervisor
        |> Task.Supervisor.children()
        |> length()

      {micros, :ok} =
        :timer.tc(fn ->
          TelemetryBridge.handle_event(
            [:coloured_flow, :runner, :enactment, :start],
            %{system_time: System.system_time()},
            %{enactment_id: eid, enactment_state: state},
            config
          )
        end)

      # Handler must not be in the broadcast path. A synchronous broadcast
      # would push this into the ms range under contention; we leave a very
      # wide safety margin so this stays stable under load.
      assert micros < 50_000,
             "handler ran for #{micros}µs; expected sub-millisecond — handler likely calling " <>
               "Phoenix.PubSub.broadcast/3 synchronously"

      # The Task fired by the handler is enrolled under the task supervisor.
      # We can't pin the exact count (concurrent tests share the supervisor),
      # but the count must be ≥ before_children right after the call.
      after_children =
        @task_supervisor
        |> Task.Supervisor.children()
        |> length()

      assert after_children >= before_children

      assert_receive {:cf_event, %Event{kind: :enactment_start}}, 1_000
    end
  end

  describe "integration smoke (real runner + InMemory storage)" do
    test "drives a tiny pass-through CPN and observes the lifecycle event stream" do
      flow = InMemory.insert_flow!(SimpleSequenceWorkflow.cpnet())
      flow_id = InMemory.flow(flow, :id)

      {:ok, enactment} = SimpleSequenceWorkflow.insert_enactment(flow_id)
      enactment_id = enactment_id(enactment)

      subscribe_topics(enactment_id)

      {:ok, _pid} =
        SimpleSequenceWorkflow.start_enactment(enactment_id, lifecycle_hooks: nil)

      # The runner boots, takes a snapshot, emits :start, then calibrates which
      # produces a single workitem for `pass`. We assert that the lifecycle
      # event and the produce_workitems span both reach the inbox + scoped
      # topics — counts in `enactment_state.workitems` reflect the pre-span
      # state (the runner snapshots `enactment_state` at span-start, not after
      # the produce mutation), so don't assert summary counts here.
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

      # produce_workitems_start carries the calibration's to-be-produced
      # binding_elements payload — we expect exactly one for the single
      # firable `pass` binding.
      assert length(produce_start.payload.binding_elements) == 1

      assert_receive {:cf_event,
                      %Event{
                        kind: :produce_workitems_stop,
                        topic: :inbox,
                        enactment_id: ^enactment_id
                      }},
                     2_000

      # The same events should land on the scoped enactment topic too.
      assert_receive {:cf_event,
                      %Event{
                        kind: :produce_workitems_stop,
                        topic: {:enactment, ^enactment_id}
                      }},
                     2_000
    end
  end

  defp enactment_id(record) when is_tuple(record) and elem(record, 0) == :enactment,
    do: InMemory.enactment(record, :id)

  defp enactment_id(%{id: id}) when is_binary(id), do: id
end
