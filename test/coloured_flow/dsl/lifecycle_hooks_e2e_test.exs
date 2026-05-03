defmodule ColouredFlow.DSL.LifecycleHooksE2ETest do
  use ColouredFlow.RepoCase, async: true
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Runner.Storage.Repo
  alias ColouredFlow.Runner.Storage.Schemas

  defmodule Workflow do
    use ColouredFlow.DSL

    name "DSL lifecycle_hooks E2E"

    colset int() :: integer()

    var x :: int()

    place :input, :int
    place :output, :int

    initial_marking :input, ~MS[1]

    transition :pass do
      input :input, bind({1, x})
      output :output, {1, x}

      action do
        # NOTE: bind in two steps. The action macro's free-var analysis treats
        # an inline `if pid = options[...] do ... end` as a CPN var (`:pid`)
        # and tries to fetch it from `event.binding`, which crashes the Task
        # silently. A separate assignment statement avoids that.
        pid = options[:test_pid]

        if pid do
          send(pid, {:action_fired, x, event.enactment_id, event.workitem.id, options})
        end
      end
    end

    on_enactment_start do
      if pid = options[:test_pid] do
        send(pid, {:enactment_start, event.enactment_id, options})
      end
    end

    on_enactment_terminate do
      if pid = options[:test_pid] do
        send(pid, {:enactment_terminate, event.enactment_id, event.reason, options})
      end
    end
  end

  defp insert_flow! do
    %Schemas.Flow{}
    |> Ecto.Changeset.cast(%{name: "DSL E2E", definition: Workflow.cpnet()}, [:name, :definition])
    |> Repo.insert!([])
  end

  describe "insert_enactment/3" do
    test "inserts an enactment row using the configured storage" do
      flow = insert_flow!()

      {:ok, enactment} = Workflow.insert_enactment(flow.id)

      assert is_binary(enactment.id)
      assert enactment.flow_id == flow.id
    end
  end

  describe "start_enactment/2" do
    test "registers the workflow module as the lifecycle_hooks (options carry test_pid)" do
      flow = insert_flow!()
      {:ok, enactment} = Workflow.insert_enactment(flow.id)

      pid =
        start_supervised!(
          {ColouredFlow.Runner.Enactment,
           enactment_id: enactment.id, lifecycle_hooks: {Workflow, [test_pid: self()]}},
          id: enactment.id
        )

      assert_receive {:enactment_start, eid, options}, 500
      assert eid == enactment.id
      assert options[:test_pid] == self()

      [wi] = get_enactment_workitems(pid)
      started = start_workitem(wi, pid)

      {:ok, _completed} =
        GenServer.call(pid, {:complete_workitems, %{started.id => []}})

      assert_receive {:action_fired, 1, ^eid, _wid, action_options}, 500
      assert action_options[:test_pid] == self()
    end

    test "passes options through {module, options} tuple" do
      flow = insert_flow!()
      {:ok, enactment} = Workflow.insert_enactment(flow.id)

      pid =
        start_supervised!(
          {ColouredFlow.Runner.Enactment,
           enactment_id: enactment.id,
           lifecycle_hooks: {Workflow, [test_pid: self(), tenant: "acme"]}},
          id: enactment.id
        )

      assert_receive {:enactment_start, _eid, options}, 500
      assert options[:tenant] == "acme"
      assert options[:test_pid] == self()

      [wi] = get_enactment_workitems(pid)
      started = start_workitem(wi, pid)

      {:ok, _completed} =
        GenServer.call(pid, {:complete_workitems, %{started.id => []}})

      assert_receive {:action_fired, 1, _eid, _wid, action_options}, 500
      assert action_options[:tenant] == "acme"
      assert action_options[:test_pid] == self()
    end
  end
end
