defmodule ColouredFlow.Runner.Enactment.Transitions.StartTest do
  use ColouredFlow.RepoCase

  alias ColouredFlow.Enactment.Marking

  alias ColouredFlow.Runner.Enactment
  alias ColouredFlow.Runner.Exceptions

  import ColouredFlow.MultiSet

  describe "start workitems" do
    setup do
      flow = :flow |> build() |> flow_with_cpnet(:simple_sequence) |> insert()
      initial_markings = [%Marking{place: "input", tokens: ~b[1]}]

      enactment =
        :enactment
        |> build(flow: flow)
        |> enactment_with_initial_markings(initial_markings)
        |> insert()

      [flow: flow, enactment: enactment]
    end

    test "works", %{enactment: enactment} do
      pid = start_link_supervised!({Enactment, enactment_id: enactment.id})

      %Enactment{workitems: workitems} = get_enactment_state(pid)
      [workitem] = Map.values(workitems)

      {:ok, [workitem]} = GenServer.call(pid, {:allocate_workitems, [workitem.id]})

      assert :allocated === workitem.state

      {:ok, [workitem]} = GenServer.call(pid, {:start_workitems, [workitem.id]})

      assert :started === workitem.state

      %Enactment{workitems: workitems} = get_enactment_state(pid)
      assert [workitem] === Map.values(workitems)
    end

    test "returns NonLiveWorkitem exception", %{enactment: enactment} do
      pid = start_link_supervised!({Enactment, enactment_id: enactment.id})

      workitem_id = Ecto.UUID.generate()

      {:error, exception} = GenServer.call(pid, {:start_workitems, [workitem_id]})

      assert %Exceptions.NonLiveWorkitem{
               id: workitem_id,
               enactment_id: enactment.id
             } === exception
    end

    test "returns InvalidWorkitemTransition", %{enactment: enactment} do
      pid = start_link_supervised!({Enactment, enactment_id: enactment.id})

      %Enactment{workitems: workitems} = get_enactment_state(pid)
      [workitem] = Map.values(workitems)

      assert {:error, exception} = GenServer.call(pid, {:start_workitems, [workitem.id]})

      assert %Exceptions.InvalidWorkitemTransition{
               id: workitem.id,
               enactment_id: enactment.id,
               state: :enabled,
               transition: :start
             } === exception
    end
  end

  defp get_enactment_state(pid) do
    :sys.get_state(pid)
  end
end
