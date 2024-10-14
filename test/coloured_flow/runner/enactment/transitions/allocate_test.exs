defmodule ColouredFlow.Runner.Enactment.Transitions.AllocateTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Runner.Exceptions

  describe "returns the allocated workitem" do
    @describetag cpnet: :simple_sequence
    @describetag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]

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
    @tag initial_markings: [%Marking{place: "place", tokens: ~MS[1]}]
    test "returns UnsufficientTokensToConsume exception", %{
      enactment_server: enactment_server,
      enactment: enactment
    } do
      [workitem_1, workitem_2] = get_enactment_workitems(enactment_server)

      assert {:error, exception} =
               GenServer.call(
                 enactment_server,
                 {:allocate_workitems, [workitem_1.id, workitem_2.id]}
               )

      assert %Exceptions.UnsufficientTokensToConsume{
               enactment_id: enactment.id,
               place: "place",
               tokens: ~MS[1]
             } === exception
    end

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[2**1]}]
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
    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    @tag cpnet: :deferred_choice
    @tag initial_markings: [%Marking{place: "place", tokens: ~MS[1]}]
    test "works", %{enactment_server: enactment_server} do
      state = get_enactment_state(enactment_server)

      [dc1_workitem, dc2_workitem] =
        state.workitems
        |> Map.values()
        |> Enum.sort_by(fn workitem -> workitem.binding_element.transition end)

      assert {:ok, [workitem]} =
               GenServer.call(enactment_server, {:allocate_workitems, [dc1_workitem.id]})

      assert :allocated === workitem.state

      [allocated_workitem] = get_enactment_workitems(enactment_server)

      assert allocated_workitem === workitem

      assert :withdrawn === Repo.get!(Schemas.Workitem, dc2_workitem.id).state
    end
  end
end
