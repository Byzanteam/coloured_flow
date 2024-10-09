defmodule ColouredFlow.Runner.Enactment.Transitions.StartTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Runner.Exceptions

  describe "start workitems" do
    @describetag cpnet: :simple_sequence
    @describetag initial_markings: [%Marking{place: "input", tokens: ~b[1]}]

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

      assert {:error, exception} =
               GenServer.call(enactment_server, {:start_workitems, [workitem.id]})

      assert %Exceptions.InvalidWorkitemTransition{
               id: workitem.id,
               enactment_id: enactment.id,
               state: :enabled,
               transition: :start
             } === exception
    end
  end
end
