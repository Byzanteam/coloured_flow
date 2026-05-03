defmodule ColouredFlow.Runner.Enactment.LifecycleHooksDispatchTest do
  # credo:disable-for-this-file Credo.Check.Readability.Specs
  use ColouredFlow.RepoCase, async: true
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Runner.Enactment.LifecycleHooks

  defmodule TestListener do
    @behaviour LifecycleHooks

    def on_enactment_start(event, options) do
      if pid = options[:test_pid], do: send(pid, {:on_enactment_start, event, options})
      :ok
    end

    def on_enactment_terminate(event, options) do
      if pid = options[:test_pid], do: send(pid, {:on_enactment_terminate, event, options})
      :ok
    end

    def on_enactment_exception(event, options) do
      if pid = options[:test_pid], do: send(pid, {:on_enactment_exception, event, options})
      :ok
    end

    def on_workitem_enabled(event, options) do
      if pid = options[:test_pid], do: send(pid, {:on_workitem_enabled, event, options})
      :ok
    end

    def on_workitem_started(event, options) do
      if pid = options[:test_pid], do: send(pid, {:on_workitem_started, event, options})
      :ok
    end

    def on_workitem_completed(event, options) do
      if pid = options[:test_pid], do: send(pid, {:on_workitem_completed, event, options})
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

    %{cpnet: cpnet}
  end

  describe "lifecycle dispatch (bare module hooks)" do
    setup :setup_flow
    setup :setup_enactment

    setup context,
      do: start_enactment(context, lifecycle_hooks: {TestListener, [test_pid: self()]})

    @tag initial_markings: []
    test "fires every callback with options carrying the test pid",
         %{enactment_server: enactment_server} do
      assert_receive {:on_enactment_start, %{enactment_id: _}, options}, 500
      assert Keyword.fetch!(options, :test_pid) == self()

      assert_receive {:on_workitem_enabled, %{enactment_id: _, workitem: wi, binding: []},
                      _options},
                     500

      assert wi.state == :enabled

      [^wi] = get_enactment_workitems(enactment_server)
      started = start_workitem(wi, enactment_server)

      assert_receive {:on_workitem_started, %{workitem: %{state: :started, id: id}}, _options},
                     500

      assert id == started.id

      {:ok, _workitems} =
        GenServer.call(enactment_server, {:complete_workitems, %{started.id => []}})

      assert_receive {:on_workitem_completed,
                      %{
                        workitem: %{state: :completed, id: ^id},
                        occurrence: %ColouredFlow.Enactment.Occurrence{}
                      }, _options},
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

    setup context,
      do:
        start_enactment(context,
          lifecycle_hooks: {TestListener, [test_pid: self(), tenant: "acme"]}
        )

    @tag initial_markings: []
    test "passes options through to every callback",
         %{enactment_server: enactment_server} do
      assert_receive {:on_enactment_start, %{enactment_id: _}, options}, 500
      assert options[:tenant] == "acme"
      assert options[:test_pid] == self()

      assert_receive {:on_workitem_enabled, %{workitem: _wi}, options}, 500
      assert options[:tenant] == "acme"

      [wi] = get_enactment_workitems(enactment_server)
      started = start_workitem(wi, enactment_server)

      assert_receive {:on_workitem_started, %{workitem: _wi}, options}, 500
      assert options[:tenant] == "acme"

      {:ok, _workitems} =
        GenServer.call(enactment_server, {:complete_workitems, %{started.id => []}})

      assert_receive {:on_workitem_completed, %{workitem: _wi, occurrence: _occ}, options}, 500
      assert options[:tenant] == "acme"
    end
  end

  describe "abnormal exit dispatches :on_enactment_exception" do
    setup :setup_flow
    setup :setup_enactment

    setup context,
      do: start_enactment(context, lifecycle_hooks: {TestListener, [test_pid: self()]})

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
