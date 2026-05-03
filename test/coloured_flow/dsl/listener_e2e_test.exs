defmodule ColouredFlow.DSL.ListenerE2ETest do
  use ColouredFlow.RepoCase, async: true
  use ColouredFlow.RunnerHelpers

  setup do
    :persistent_term.put({__MODULE__, :pid}, self())
    on_exit(fn -> :persistent_term.erase({__MODULE__, :pid}) end)
    :ok
  end

  defp test_pid, do: :persistent_term.get({__MODULE__, :pid}, nil)

  defmodule Workflow do
    use ColouredFlow.DSL,
      storage: ColouredFlow.Runner.Storage.Default

    name "DSL listener E2E"

    colset int() :: integer()

    var x :: int()

    place :input, :int
    place :output, :int

    initial_marking :input, ~MS[1]

    transition :pass do
      input :input, bind({1, x})
      output :output, {1, x}

      action do
        pid = :persistent_term.get({ColouredFlow.DSL.ListenerE2ETest, :pid}, nil)
        if pid, do: send(pid, {:action_fired, x, ctx.enactment_id, workitem.id, extras})
      end
    end

    on_enactment_start do
      pid = :persistent_term.get({ColouredFlow.DSL.ListenerE2ETest, :pid}, nil)
      if pid, do: send(pid, {:enactment_start, ctx.enactment_id, extras})
    end

    on_enactment_terminate reason do
      pid = :persistent_term.get({ColouredFlow.DSL.ListenerE2ETest, :pid}, nil)
      if pid, do: send(pid, {:enactment_terminate, ctx.enactment_id, reason, extras})
    end
  end

  describe "setup_flow!" do
    test "inserts a row each call (not idempotent)" do
      flow1 = Workflow.setup_flow!()
      flow2 = Workflow.setup_flow!()

      refute flow1.id == flow2.id
    end
  end

  describe "start_enactment" do
    test "registers the workflow module as the listener (default extras = nil)" do
      assert is_pid(test_pid())
      flow = Workflow.setup_flow!()
      enactment = Workflow.insert_enactment!(flow)

      pid =
        start_supervised!(
          {ColouredFlow.Runner.Enactment, enactment_id: enactment.id, listener: Workflow},
          id: enactment.id
        )

      assert_receive {:enactment_start, eid, nil}, 500
      assert eid == enactment.id

      [wi] = get_enactment_workitems(pid)
      started = start_workitem(wi, pid)

      {:ok, _completed} =
        GenServer.call(pid, {:complete_workitems, %{started.id => []}})

      assert_receive {:action_fired, 1, ^eid, _wid, nil}, 500
    end

    test "passes extras through {module, extras} listener tuple" do
      assert is_pid(test_pid())
      flow = Workflow.setup_flow!()
      enactment = Workflow.insert_enactment!(flow)

      pid =
        start_supervised!(
          {ColouredFlow.Runner.Enactment,
           enactment_id: enactment.id, listener: {Workflow, %{tenant: "acme"}}},
          id: enactment.id
        )

      assert_receive {:enactment_start, _eid, %{tenant: "acme"}}, 500

      [wi] = get_enactment_workitems(pid)
      started = start_workitem(wi, pid)

      {:ok, _completed} =
        GenServer.call(pid, {:complete_workitems, %{started.id => []}})

      assert_receive {:action_fired, 1, _eid, _wid, %{tenant: "acme"}}, 500
    end
  end
end
