defmodule ColouredFlow.Runner.Enactment.ListenerDispatchTest do
  # credo:disable-for-this-file Credo.Check.Readability.Specs
  use ColouredFlow.RepoCase, async: true
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Runner.Enactment.Listener

  defmodule TestListener do
    @behaviour Listener

    def on_enactment_start(ctx, extras) do
      send_to_pid({:on_enactment_start, ctx, extras})
    end

    def on_enactment_terminate(ctx, reason, extras) do
      send_to_pid({:on_enactment_terminate, ctx, reason, extras})
    end

    def on_enactment_exception(ctx, reason, extras) do
      send_to_pid({:on_enactment_exception, ctx, reason, extras})
    end

    def on_workitem_enabled(ctx, workitem, extras) do
      send_to_pid({:on_workitem_enabled, ctx, workitem, extras})
    end

    def on_workitem_started(ctx, workitem, extras) do
      send_to_pid({:on_workitem_started, ctx, workitem, extras})
    end

    def on_workitem_completed(ctx, workitem, occurrence, extras) do
      send_to_pid({:on_workitem_completed, ctx, workitem, occurrence, extras})
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

    :persistent_term.put({TestListener, :test_pid}, self())
    on_exit(fn -> :persistent_term.erase({TestListener, :test_pid}) end)

    %{cpnet: cpnet}
  end

  describe "lifecycle dispatch (bare module listener)" do
    setup :setup_flow
    setup :setup_enactment
    setup context, do: start_enactment(context, listener: TestListener)

    @tag initial_markings: []
    test "fires every callback with extras = nil",
         %{enactment_server: enactment_server} do
      assert_receive {:on_enactment_start, %{enactment_id: _}, nil}, 500

      assert_receive {:on_workitem_enabled, %{enactment_id: _},
                      %ColouredFlow.Runner.Enactment.Workitem{state: :enabled} = wi, nil},
                     500

      [^wi] = get_enactment_workitems(enactment_server)
      started = start_workitem(wi, enactment_server)

      assert_receive {:on_workitem_started, _ctx, %{state: :started, id: id}, nil}, 500
      assert id == started.id

      {:ok, _workitems} =
        GenServer.call(enactment_server, {:complete_workitems, %{started.id => []}})

      assert_receive {:on_workitem_completed, _ctx, %{state: :completed, id: ^id},
                      %ColouredFlow.Enactment.Occurrence{}, nil},
                     500
    end
  end

  describe "lifecycle dispatch ({module, extras} listener)" do
    setup :setup_flow
    setup :setup_enactment
    setup context, do: start_enactment(context, listener: {TestListener, %{tenant: "acme"}})

    @tag initial_markings: []
    test "appends extras as last arg of every callback",
         %{enactment_server: enactment_server} do
      assert_receive {:on_enactment_start, %{enactment_id: _}, %{tenant: "acme"}}, 500

      assert_receive {:on_workitem_enabled, _ctx, _wi, %{tenant: "acme"}}, 500

      [wi] = get_enactment_workitems(enactment_server)
      started = start_workitem(wi, enactment_server)

      assert_receive {:on_workitem_started, _ctx, _wi, %{tenant: "acme"}}, 500

      {:ok, _workitems} =
        GenServer.call(enactment_server, {:complete_workitems, %{started.id => []}})

      assert_receive {:on_workitem_completed, _ctx, _wi, _occurrence, %{tenant: "acme"}}, 500
    end
  end
end
