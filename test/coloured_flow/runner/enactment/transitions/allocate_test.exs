defmodule ColouredFlow.Runner.Enactment.Transitions.AllocateTest do
  use ColouredFlow.RepoCase

  alias ColouredFlow.Enactment.Marking

  alias ColouredFlow.Runner.Enactment
  alias ColouredFlow.Runner.Exceptions

  import ColouredFlow.MultiSet

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
    {:ok, pid} = GenServer.start_link(Enactment, enactment_id: enactment.id)

    %Enactment{workitems: [workitem]} = get_enactment_state(pid)

    assert {:ok, workitem} = GenServer.call(pid, {:allocate_workitem, workitem.id})
    assert :allocated === workitem.state
  end

  test "returns InvalidWorkitemTransition exception", %{enactment: enactment} do
    {:ok, pid} = GenServer.start_link(Enactment, enactment_id: enactment.id)

    %Enactment{workitems: [workitem]} = get_enactment_state(pid)

    assert {:ok, workitem} = GenServer.call(pid, {:allocate_workitem, workitem.id})
    assert :allocated === workitem.state

    assert {:error, exception} = GenServer.call(pid, {:allocate_workitem, workitem.id})

    assert %Exceptions.InvalidWorkitemTransition{
             id: workitem.id,
             enactment_id: enactment.id,
             state: :allocated,
             transition: :allocate
           } === exception
  end

  test "returns NonLiveWorkitem exception", %{enactment: enactment} do
    {:ok, pid} = GenServer.start_link(Enactment, enactment_id: enactment.id)

    workitem_id = Ecto.UUID.generate()
    assert {:error, exception} = GenServer.call(pid, {:allocate_workitem, workitem_id})

    assert %Exceptions.NonLiveWorkitem{
             id: workitem_id,
             enactment_id: enactment.id
           } === exception
  end

  defp get_enactment_state(pid) do
    :sys.get_state(pid)
  end
end
