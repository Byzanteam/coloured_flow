defmodule ColouredFlow.Runner.Enactment.LifecycleHooksDispatchTest do
  # credo:disable-for-this-file Credo.Check.Readability.Specs
  use ColouredFlow.RepoCase, async: true
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Runner.Enactment.LifecycleHooks

  defmodule TestListener do
    @behaviour LifecycleHooks

    def on_enactment_start(event, options) do
      send_to_pid({:on_enactment_start, event, options})
    end

    def on_enactment_terminate(event, options) do
      send_to_pid({:on_enactment_terminate, event, options})
    end

    def on_enactment_exception(event, options) do
      send_to_pid({:on_enactment_exception, event, options})
    end

    def on_workitem_enabled(event, options) do
      send_to_pid({:on_workitem_enabled, event, options})
    end

    def on_workitem_started(event, options) do
      send_to_pid({:on_workitem_started, event, options})
    end

    def on_workitem_completed(event, options) do
      send_to_pid({:on_workitem_completed, event, options})
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

  describe "lifecycle dispatch (bare module hooks)" do
    setup :setup_flow
    setup :setup_enactment
    setup context, do: start_enactment(context, lifecycle_hooks: TestListener)

    @tag initial_markings: []
    test "fires every callback with options = []",
         %{enactment_server: enactment_server} do
      assert_receive {:on_enactment_start, %{enactment_id: _}, []}, 500

      assert_receive {:on_workitem_enabled, %{enactment_id: _, workitem: wi, binding: []}, []},
                     500

      assert wi.state == :enabled

      [^wi] = get_enactment_workitems(enactment_server)
      started = start_workitem(wi, enactment_server)

      assert_receive {:on_workitem_started, %{workitem: %{state: :started, id: id}}, []}, 500
      assert id == started.id

      {:ok, _workitems} =
        GenServer.call(enactment_server, {:complete_workitems, %{started.id => []}})

      assert_receive {:on_workitem_completed,
                      %{
                        workitem: %{state: :completed, id: ^id},
                        occurrence: %ColouredFlow.Enactment.Occurrence{}
                      }, []},
                     500
    end
  end

  describe "malformed lifecycle_hooks" do
    setup :setup_flow
    setup :setup_enactment

    @tag initial_markings: []
    test "non-atom non-tuple value raises ArgumentError from start_link",
         %{enactment: enactment} do
      # `start_supervised!` wraps the underlying `ArgumentError` in a
      # `RuntimeError` whose message embeds the original exception type and
      # reason. Match on the wrapped form.
      assert_raise RuntimeError, ~r/ArgumentError.*:lifecycle_hooks/s, fn ->
        start_supervised!(
          {ColouredFlow.Runner.Enactment, enactment_id: enactment.id, lifecycle_hooks: "garbage"},
          id: enactment.id
        )
      end
    end
  end

  describe "lifecycle dispatch ({module, options} hooks)" do
    setup :setup_flow
    setup :setup_enactment
    setup context, do: start_enactment(context, lifecycle_hooks: {TestListener, tenant: "acme"})

    @tag initial_markings: []
    test "passes options through to every callback",
         %{enactment_server: enactment_server} do
      assert_receive {:on_enactment_start, %{enactment_id: _}, [tenant: "acme"]}, 500

      assert_receive {:on_workitem_enabled, %{workitem: _wi}, [tenant: "acme"]}, 500

      [wi] = get_enactment_workitems(enactment_server)
      started = start_workitem(wi, enactment_server)

      assert_receive {:on_workitem_started, %{workitem: _wi}, [tenant: "acme"]}, 500

      {:ok, _workitems} =
        GenServer.call(enactment_server, {:complete_workitems, %{started.id => []}})

      assert_receive {:on_workitem_completed, %{workitem: _wi, occurrence: _occ},
                      [tenant: "acme"]},
                     500
    end
  end

  describe "abnormal exit dispatches :on_enactment_exception" do
    setup :setup_flow
    setup :setup_enactment
    setup context, do: start_enactment(context, lifecycle_hooks: TestListener)

    @tag initial_markings: []
    test "non-normal stop -> on_enactment_exception with reason :abnormal_exit",
         %{enactment_server: enactment_server} do
      # Drain the boot-time start event so we don't false-positive.
      assert_receive {:on_enactment_start, _event, _options}, 500

      # `GenServer.stop/3` with a non-`:normal`/`:shutdown` reason routes
      # through `terminate(reason, state)`, which is the path that records
      # the abnormal-exit exception and dispatches `:on_enactment_exception`.
      GenServer.stop(enactment_server, :something_bad, 1000)

      assert_receive {:on_enactment_exception, %{reason: :abnormal_exit}, _options}, 500
    end
  end
end
