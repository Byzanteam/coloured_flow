defmodule ColouredFlow.Runner.Enactment.Transitions.AllocateTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Runner.Exceptions

  describe "returns the allocated workitem" do
    @describetag cpnet: :simple_sequence
    @describetag initial_markings: [%Marking{place: "input", tokens: ~b[1]}]

    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    test "works", %{enactment_server: enactment_server} do
      [workitem] = get_enactment_workitems(enactment_server)

      assert {:ok, [workitem]} =
               GenServer.call(enactment_server, {:allocate_workitems, [workitem.id]})

      assert :allocated === workitem.state
    end

    test "returns InvalidWorkitemTransition exception", %{
      enactment_server: enactment_server,
      enactment: enactment
    } do
      [workitem] = get_enactment_workitems(enactment_server)

      assert {:ok, [workitem]} =
               GenServer.call(enactment_server, {:allocate_workitems, [workitem.id]})

      assert :allocated === workitem.state

      assert {:error, exception} =
               GenServer.call(enactment_server, {:allocate_workitems, [workitem.id]})

      assert %Exceptions.InvalidWorkitemTransition{
               id: workitem.id,
               enactment_id: enactment.id,
               state: :allocated,
               transition: :allocate
             } === exception
    end

    test "returns NonLiveWorkitem exception", %{
      enactment_server: enactment_server,
      enactment: enactment
    } do
      workitem_id = Ecto.UUID.generate()

      assert {:error, exception} =
               GenServer.call(enactment_server, {:allocate_workitems, [workitem_id]})

      assert %Exceptions.NonLiveWorkitem{
               id: workitem_id,
               enactment_id: enactment.id
             } === exception
    end

    @tag cpnet: :deferred_choice
    @tag initial_markings: [%Marking{place: "input", tokens: ~b[2**1]}]
    test "returns UnsufficientTokensToConsume exception", %{
      enactment_server: enactment_server,
      enactment: enactment
    } do
      [workitem_1, _workitem_2, workitem_3] = get_enactment_workitems(enactment_server)

      assert {:error, exception} =
               GenServer.call(
                 enactment_server,
                 {:allocate_workitems, [workitem_1.id, workitem_3.id]}
               )

      assert %Exceptions.UnsufficientTokensToConsume{
               enactment_id: enactment.id,
               place: "input",
               tokens: ~b[2**1]
             } === exception
    end

    @tag initial_markings: [%Marking{place: "input", tokens: ~b[2**1]}]
    test "allocates multiple workitems", %{enactment_server: enactment_server} do
      [workitem_1, workitem_2] = get_enactment_workitems(enactment_server)

      assert {:ok, [workitem_1, workitem_2]} =
               GenServer.call(
                 enactment_server,
                 {:allocate_workitems, [workitem_1.id, workitem_2.id]}
               )

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
      enactment_server = start_link_supervised!({Enactment, enactment_id: enactment.id})
      state = get_enactment_state(enactment_server)

      [pt1_workitem_1, pt1_workitem_2, pt2_workitem] =
        state.workitems
        |> Map.values()
        |> Enum.sort_by(fn workitem -> workitem.binding_element.transition end)

      assert {:ok, [workitem]} =
               GenServer.call(enactment_server, {:allocate_workitems, [pt1_workitem_1.id]})

      assert :allocated === workitem.state

      new_state = get_enactment_state(enactment_server)

      [allocated_workitem, enabled_item] =
        new_state.workitems |> Map.values() |> Enum.sort_by(& &1.state)

      assert allocated_workitem === workitem
      assert enabled_item === pt1_workitem_2

      assert :withdrawn === Repo.get!(Schemas.Workitem, pt2_workitem.id).state
    end
  end
end
