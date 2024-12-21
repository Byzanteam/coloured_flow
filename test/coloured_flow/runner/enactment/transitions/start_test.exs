defmodule ColouredFlow.Runner.Enactment.Transitions.StartTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Runner.Exceptions

  describe "returns the started workitem" do
    @describetag cpnet: :simple_sequence
    @describetag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]

    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    test "works", %{enactment_server: enactment_server} do
      [workitem] = get_enactment_workitems(enactment_server)

      assert {:ok, [workitem]} =
               GenServer.call(enactment_server, {:start_workitems, [workitem.id]})

      assert :started === workitem.state
    end

    test "returns InvalidWorkitemTransition exception", %{
      enactment_server: enactment_server,
      enactment: enactment
    } do
      [workitem] = get_enactment_workitems(enactment_server)

      assert {:ok, [workitem]} =
               GenServer.call(enactment_server, {:start_workitems, [workitem.id]})

      assert :started === workitem.state

      assert {:error, exception} =
               GenServer.call(enactment_server, {:start_workitems, [workitem.id]})

      assert %Exceptions.InvalidWorkitemTransition{
               id: workitem.id,
               enactment_id: enactment.id,
               state: :started,
               transition: :start
             } === exception
    end

    test "returns NonLiveWorkitem exception", %{
      enactment_server: enactment_server,
      enactment: enactment
    } do
      workitem_id = Ecto.UUID.generate()

      assert {:error, exception} =
               GenServer.call(enactment_server, {:start_workitems, [workitem_id]})

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
                 {:start_workitems, [workitem_1.id, workitem_2.id]}
               )

      assert %Exceptions.UnsufficientTokensToConsume{
               enactment_id: enactment.id,
               place: "place",
               tokens: ~MS[1]
             } === exception
    end

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[2**1]}]
    test "starts multiple workitems", %{enactment_server: enactment_server} do
      [workitem_1, workitem_2] = get_enactment_workitems(enactment_server)

      assert {:ok, [workitem_1, workitem_2]} =
               GenServer.call(
                 enactment_server,
                 {:start_workitems, [workitem_1.id, workitem_2.id]}
               )

      assert :started === workitem_1.state
      assert :started === workitem_2.state
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
               GenServer.call(enactment_server, {:start_workitems, [dc1_workitem.id]})

      assert :started === workitem.state

      [started_workitem] = get_enactment_workitems(enactment_server)

      assert started_workitem === workitem

      assert :withdrawn === Repo.get!(Schemas.Workitem, dc2_workitem.id).state
    end
  end
end
