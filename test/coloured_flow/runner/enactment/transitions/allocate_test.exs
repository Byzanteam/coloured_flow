defmodule ColouredFlow.Runner.Enactment.Transitions.AllocateTest do
  use ColouredFlow.RepoCase

  alias ColouredFlow.Enactment.Marking

  alias ColouredFlow.Runner.Enactment
  alias ColouredFlow.Runner.Exceptions

  import ColouredFlow.MultiSet

  describe "returns the allocated workitem" do
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

      %Enactment{workitems: [workitem]} = get_enactment_state(pid)

      assert {:ok, [workitem]} = GenServer.call(pid, {:allocate_workitems, [workitem.id]})
      assert :allocated === workitem.state
    end

    test "returns InvalidWorkitemTransition exception", %{enactment: enactment} do
      pid = start_link_supervised!({Enactment, enactment_id: enactment.id})

      %Enactment{workitems: [workitem]} = get_enactment_state(pid)

      assert {:ok, [workitem]} = GenServer.call(pid, {:allocate_workitems, [workitem.id]})
      assert :allocated === workitem.state

      assert {:error, exception} = GenServer.call(pid, {:allocate_workitems, [workitem.id]})

      assert %Exceptions.InvalidWorkitemTransition{
               id: workitem.id,
               enactment_id: enactment.id,
               state: :allocated,
               transition: :allocate
             } === exception
    end

    test "returns NonLiveWorkitem exception", %{enactment: enactment} do
      pid = start_link_supervised!({Enactment, enactment_id: enactment.id})

      workitem_id = Ecto.UUID.generate()
      assert {:error, exception} = GenServer.call(pid, {:allocate_workitems, [workitem_id]})

      assert %Exceptions.NonLiveWorkitem{
               id: workitem_id,
               enactment_id: enactment.id
             } === exception
    end

    test "returns UnsufficientTokensToConsume exception" do
      flow = :flow |> build() |> flow_with_cpnet(:deferred_choice) |> insert()

      initial_markings = [
        %Marking{place: "input", tokens: ~b[2**1]}
      ]

      enactment =
        :enactment
        |> build(flow: flow)
        |> enactment_with_initial_markings(initial_markings)
        |> insert()

      pid = start_link_supervised!({Enactment, enactment_id: enactment.id})

      %Enactment{workitems: [workitem_1, _workitem_2, workitem_3]} = get_enactment_state(pid)

      assert {:error, exception} =
               GenServer.call(pid, {:allocate_workitems, [workitem_1.id, workitem_3.id]})

      assert %Exceptions.UnsufficientTokensToConsume{
               enactment_id: enactment.id,
               place: "input",
               tokens: ~b[2**1]
             } === exception
    end

    test "allocates multiple workitems", %{flow: flow} do
      initial_markings = [%Marking{place: "input", tokens: ~b[2**1]}]

      enactment =
        :enactment
        |> build(flow: flow)
        |> enactment_with_initial_markings(initial_markings)
        |> insert()

      pid = start_link_supervised!({Enactment, enactment_id: enactment.id})

      %Enactment{workitems: [workitem_1, workitem_2]} = get_enactment_state(pid)

      assert {:ok, [workitem_1, workitem_2]} =
               GenServer.call(pid, {:allocate_workitems, [workitem_1.id, workitem_2.id]})

      assert :allocated === workitem_1.state
      assert :allocated === workitem_2.state
    end
  end

  describe "calibrates workitems" do
    setup do
      flow = :flow |> build() |> flow_with_cpnet(:deferred_choice) |> insert()
      initial_markings = [%Marking{place: "input", tokens: ~b[2**1]}]

      enactment =
        :enactment
        |> build(flow: flow)
        |> enactment_with_initial_markings(initial_markings)
        |> insert()

      [flow: flow, enactment: enactment]
    end

    test "works", %{enactment: enactment} do
      pid = start_link_supervised!({Enactment, enactment_id: enactment.id})
      state = get_enactment_state(pid)

      [pt1_workitem_1, pt1_workitem_2, pt2_workitem] =
        Enum.sort_by(state.workitems, fn workitem -> workitem.binding_element.transition end)

      assert {:ok, [workitem]} = GenServer.call(pid, {:allocate_workitems, [pt1_workitem_1.id]})
      assert :allocated === workitem.state

      new_state = get_enactment_state(pid)
      [allocated_workitem, enabled_item] = Enum.sort_by(new_state.workitems, & &1.state)

      assert allocated_workitem === workitem
      assert enabled_item === pt1_workitem_2

      assert :withdrawn === Repo.get!(Schemas.Workitem, pt2_workitem.id).state
    end
  end

  defp get_enactment_state(pid) do
    :sys.get_state(pid)
  end
end
