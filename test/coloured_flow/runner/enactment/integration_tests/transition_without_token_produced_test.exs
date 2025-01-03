defmodule ColouredFlow.Runner.Enactment.IntegrationTests.TransitionWithoutTokenProducedTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Enactment.BindingElement

  setup do
    use ColouredFlow.DefinitionHelpers

    import ColouredFlow.Notation

    # ```mermaid
    # flowchart TB
    #   %% The remove_trigger doesn't produce tokens.
    #
    #   %% colset int() :: integer()
    #
    #   t((trigger))
    #   o((output))
    #
    #   rt[remove_trigger]
    #
    #   t --bind {1,1}--> rt
    #   rt --{0,1}--> o
    # ```
    cpnet =
      %ColouredPetriNet{
        colour_sets: [
          colset(int() :: integer())
        ],
        places: [
          %Place{name: "trigger", colour_set: :int},
          %Place{name: "output", colour_set: :int}
        ],
        transitions: [
          build_transition!(name: "remove_trigger")
        ],
        arcs: [
          arc(remove_trigger <~ trigger :: "bind {1, 1}"),
          arc(remove_trigger ~> output :: "{0, 1}")
        ]
      }

    %{cpnet: cpnet}
  end

  describe "validates definition" do
    test "works", %{cpnet: cpnet} do
      assert {:ok, _cpnet} =
               cpnet
               |> ColouredFlow.Builder.build()
               |> ColouredFlow.Validators.run()
    end
  end

  describe "enactment" do
    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    @tag initial_markings: [%Marking{place: "trigger", tokens: ~MS[1]}]
    test "works", %{enactment: enactment, enactment_server: enactment_server} do
      assert [
               %Enactment.Workitem{
                 state: :enabled,
                 binding_element: %BindingElement{
                   transition: "remove_trigger",
                   binding: [],
                   to_consume: [%Marking{place: "trigger", tokens: ~MS[1]}]
                 }
               } = workitem
             ] = get_enactment_workitems(enactment_server)

      {:ok, _workitems} =
        GenServer.call(
          enactment_server,
          {:complete_workitems, %{workitem.id => []}}
        )

      wait_enactment_to_stop!(enactment_server)

      assert %Schemas.Workitem{state: :completed} =
               Repo.get!(Schemas.Workitem, workitem.id)

      assert %Schemas.EnactmentLog{
               state: :terminated,
               termination: %Schemas.EnactmentLog.Termination{
                 type: :implicit,
                 message: nil
               }
             } = Repo.get_by!(Schemas.EnactmentLog, enactment_id: enactment.id)

      assert %Schemas.Enactment{
               state: :terminated,
               final_markings: []
             } = Repo.get!(Schemas.Enactment, enactment.id)
    end
  end
end
