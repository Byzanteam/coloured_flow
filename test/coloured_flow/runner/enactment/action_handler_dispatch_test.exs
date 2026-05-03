defmodule ColouredFlow.Runner.Enactment.ActionHandlerDispatchTest do
  use ColouredFlow.RepoCase, async: true
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Runner.ActionHandler

  defmodule TestHandler do
    @behaviour ActionHandler

    def on_enactment_start(ctx) do
      send_to_pid({:on_enactment_start, ctx})
    end

    def on_enactment_terminate(ctx, reason) do
      send_to_pid({:on_enactment_terminate, ctx, reason})
    end

    def on_enactment_exception(ctx, reason) do
      send_to_pid({:on_enactment_exception, ctx, reason})
    end

    def on_workitem_enabled(ctx, workitem) do
      send_to_pid({:on_workitem_enabled, ctx, workitem})
    end

    def on_workitem_started(ctx, workitem) do
      send_to_pid({:on_workitem_started, ctx, workitem})
    end

    def on_workitem_completed(ctx, workitem, occurrence) do
      send_to_pid({:on_workitem_completed, ctx, workitem, occurrence})
    end

    defp send_to_pid(msg) do
      pid = :persistent_term.get({__MODULE__, :test_pid}, nil)
      if pid, do: send(pid, msg)
      :ok
    end
  end

  setup do
    use ColouredFlow.DefinitionHelpers

    import ColouredFlow.Notation

    # `produce_trigger` always enabled — emits {1, 1} into `trigger`.
    cpnet =
      %ColouredPetriNet{
        colour_sets: [
          colset(int() :: integer())
        ],
        places: [
          %Place{name: "trigger", colour_set: :int}
        ],
        transitions: [
          build_transition!(name: "produce_trigger")
        ],
        arcs: [
          arc(produce_trigger ~> trigger :: "{1, 1}")
        ]
      }

    :persistent_term.put({TestHandler, :test_pid}, self())
    on_exit(fn -> :persistent_term.erase({TestHandler, :test_pid}) end)

    %{cpnet: cpnet}
  end

  describe "lifecycle dispatch" do
    setup :setup_flow
    setup :setup_enactment
    setup context, do: start_enactment(context, action_handler: TestHandler)

    @tag initial_markings: []
    test "fires on_enactment_start, on_workitem_enabled, on_workitem_started, on_workitem_completed",
         %{enactment_server: enactment_server} do
      assert_receive {:on_enactment_start, %{enactment_id: _}}, 500

      assert_receive {:on_workitem_enabled, %{enactment_id: _},
                      %ColouredFlow.Runner.Enactment.Workitem{state: :enabled} = wi},
                     500

      [^wi] = get_enactment_workitems(enactment_server)
      started = start_workitem(wi, enactment_server)

      assert_receive {:on_workitem_started, _ctx, %{state: :started, id: id}}, 500
      assert id == started.id

      {:ok, _workitems} =
        GenServer.call(
          enactment_server,
          {:complete_workitems, %{started.id => []}}
        )

      assert_receive {:on_workitem_completed, _ctx, %{state: :completed, id: ^id},
                      %ColouredFlow.Enactment.Occurrence{}},
                     500
    end
  end
end
