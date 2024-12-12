defmodule ColouredFlow.Runner.Enactment.Transitions.StartTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Runner.Exceptions

  describe "start workitems" do
    @describetag cpnet: :simple_sequence
    @describetag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]

    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    test "works", %{enactment_server: enactment_server} do
      [workitem] = get_enactment_workitems(enactment_server)

      {:ok, [workitem]} = GenServer.call(enactment_server, {:allocate_workitems, [workitem.id]})

      assert :allocated === workitem.state

      {:ok, [workitem]} = GenServer.call(enactment_server, {:start_workitems, [workitem.id]})

      assert :started === workitem.state

      assert [workitem] === get_enactment_workitems(enactment_server)
    end

    test "works for starting enabled workitems", %{enactment_server: enactment_server} do
      [workitem] = get_enactment_workitems(enactment_server)

      assert {:ok, [workitem]} =
               GenServer.call(enactment_server, {:start_workitems, [workitem.id]})

      assert :started === workitem.state
    end

    test "returns NonLiveWorkitem exception", %{
      enactment_server: enactment_server,
      enactment: enactment
    } do
      workitem_id = Ecto.UUID.generate()

      {:error, exception} = GenServer.call(enactment_server, {:start_workitems, [workitem_id]})

      assert %Exceptions.NonLiveWorkitem{
               id: workitem_id,
               enactment_id: enactment.id
             } === exception
    end

    test "returns InvalidWorkitemTransition", %{
      enactment_server: enactment_server,
      enactment: enactment
    } do
      [workitem] = get_enactment_workitems(enactment_server)

      {:ok, [workitem]} = GenServer.call(enactment_server, {:start_workitems, [workitem.id]})

      assert {:error, exception} =
               GenServer.call(enactment_server, {:start_workitems, [workitem.id]})

      assert %Exceptions.InvalidWorkitemTransition{
               id: workitem.id,
               enactment_id: enactment.id,
               state: :started,
               transition: :start_e
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
  end

  describe "calibrates workitems for starting enabled workitems" do
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

      assert [workitem] === get_enactment_workitems(enactment_server)

      assert :withdrawn === Repo.get!(Schemas.Workitem, dc2_workitem.id).state
    end
  end
end
