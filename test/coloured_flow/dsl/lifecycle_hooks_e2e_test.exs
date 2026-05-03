defmodule ColouredFlow.DSL.LifecycleHooksE2ETest do
  use ColouredFlow.RepoCase, async: true
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Runner.Storage.Repo
  alias ColouredFlow.Runner.Storage.Schemas

  setup do
    :persistent_term.put({__MODULE__, :pid}, self())
    on_exit(fn -> :persistent_term.erase({__MODULE__, :pid}) end)
    :ok
  end

  defp test_pid, do: :persistent_term.get({__MODULE__, :pid}, nil)

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
        pid = :persistent_term.get({ColouredFlow.DSL.LifecycleHooksE2ETest, :pid}, nil)

        if pid do
          send(pid, {:action_fired, x, event.enactment_id, event.workitem.id, options})
        end
      end
    end

    on_enactment_start do
      pid = :persistent_term.get({ColouredFlow.DSL.LifecycleHooksE2ETest, :pid}, nil)
      if pid, do: send(pid, {:enactment_start, event.enactment_id, options})
    end

    on_enactment_terminate do
      pid = :persistent_term.get({ColouredFlow.DSL.LifecycleHooksE2ETest, :pid}, nil)
      if pid, do: send(pid, {:enactment_terminate, event.enactment_id, event.reason, options})
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
    test "registers the workflow module as the lifecycle_hooks (default options = [])" do
      assert is_pid(test_pid())
      flow = insert_flow!()
      {:ok, enactment} = Workflow.insert_enactment(flow.id)

      pid =
        start_supervised!(
          {ColouredFlow.Runner.Enactment, enactment_id: enactment.id, lifecycle_hooks: Workflow},
          id: enactment.id
        )

      assert_receive {:enactment_start, eid, []}, 500
      assert eid == enactment.id

      [wi] = get_enactment_workitems(pid)
      started = start_workitem(wi, pid)

      {:ok, _completed} =
        GenServer.call(pid, {:complete_workitems, %{started.id => []}})

      assert_receive {:action_fired, 1, ^eid, _wid, []}, 500
    end

    test "passes options through {module, options} tuple" do
      assert is_pid(test_pid())
      flow = insert_flow!()
      {:ok, enactment} = Workflow.insert_enactment(flow.id)

      pid =
        start_supervised!(
          {ColouredFlow.Runner.Enactment,
           enactment_id: enactment.id, lifecycle_hooks: {Workflow, tenant: "acme"}},
          id: enactment.id
        )

      assert_receive {:enactment_start, _eid, [tenant: "acme"]}, 500

      [wi] = get_enactment_workitems(pid)
      started = start_workitem(wi, pid)

      {:ok, _completed} =
        GenServer.call(pid, {:complete_workitems, %{started.id => []}})

      assert_receive {:action_fired, 1, _eid, _wid, [tenant: "acme"]}, 500
    end
  end
end
