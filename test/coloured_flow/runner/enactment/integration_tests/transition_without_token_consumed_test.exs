defmodule ColouredFlow.Runner.Enactment.IntegrationTests.TransitionWithoutTokenConsumedTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Enactment.BindingElement

  setup do
    use ColouredFlow.DefinitionHelpers

    import ColouredFlow.Notation

    # ```mermaid
    # flowchart TB
    #   %% The remove_trigger doesn't consume tokens.
    #
    #   %% colset int() :: integer()
    #
    #   t((trigger))
    #   i((input))
    #   o((output))
    #
    #   rt[remove_trigger]
    #   art[alternative_remove_trigger]
    #
    #   t --bind {0,1}--> rt
    #   rt --{0,1}--> o
    #   i --bind {1,1}--> art
    #   t --bind {0,1}-->art
    #   art --{0,1}--> o
    # ```
    cpnet =
      %ColouredPetriNet{
        colour_sets: [
          colset(int() :: integer())
        ],
        places: [
          %Place{name: "trigger", colour_set: :int},
          %Place{name: "input", colour_set: :int},
          %Place{name: "output", colour_set: :int}
        ],
        transitions: [
          build_transition!(name: "remove_trigger"),
          build_transition!(name: "alternative_remove_trigger")
        ],
        arcs: [
          arc(remove_trigger <~ trigger :: "bind {0, 1}"),
          arc(remove_trigger ~> output :: "{0, 1}"),
          arc(alternative_remove_trigger <~ trigger :: "bind {0, 1}"),
          arc(alternative_remove_trigger <~ input :: "bind {1, 1}"),
          arc(alternative_remove_trigger ~> output :: "{0, 1}")
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
    test "works", %{enactment_server: enactment_server} do
      assert [
               %Enactment.Workitem{
                 state: :enabled,
                 binding_element: %BindingElement{
                   transition: "remove_trigger",
                   binding: [],
                   to_consume: [%Marking{place: "trigger", tokens: ~MS[]}]
                 }
               } = workitem
             ] = get_enactment_workitems(enactment_server)

      {:ok, _workitems} =
        GenServer.call(
          enactment_server,
          {:complete_workitems, %{workitem.id => []}}
        )

      wait_enactment_requests_handled!(enactment_server)

      assert Process.alive?(enactment_server)

      assert %Schemas.Workitem{state: :completed} =
               Repo.get!(Schemas.Workitem, workitem.id)

      assert [
               %Enactment.Workitem{
                 state: :enabled,
                 binding_element: %BindingElement{
                   transition: "remove_trigger",
                   binding: [],
                   to_consume: [%Marking{place: "trigger", tokens: ~MS[]}]
                 }
               } = new_workitem
             ] = get_enactment_workitems(enactment_server)

      refute new_workitem.id === workitem.id
    end

    @tag initial_markings: [
           %Marking{place: "trigger", tokens: ~MS[1]},
           %Marking{place: "input", tokens: ~MS[1]}
         ]
    test "works while one of input places consumes non-zero tokens",
         %{enactment_server: enactment_server} do
      assert [
               %Enactment.Workitem{
                 state: :enabled,
                 binding_element: %BindingElement{
                   transition: "alternative_remove_trigger",
                   binding: [],
                   to_consume: [
                     %Marking{place: "input", tokens: ~MS[1]},
                     %Marking{place: "trigger", tokens: ~MS[]}
                   ]
                 }
               } = alternative_workitem,
               %Enactment.Workitem{
                 state: :enabled,
                 binding_element: %BindingElement{
                   transition: "remove_trigger",
                   binding: [],
                   to_consume: [%Marking{place: "trigger", tokens: ~MS[]}]
                 }
               } = workitem
             ] = get_enactment_workitems(enactment_server)

      {:ok, _workitems} =
        GenServer.call(
          enactment_server,
          {:complete_workitems, %{alternative_workitem.id => []}}
        )

      wait_enactment_requests_handled!(enactment_server)

      assert Process.alive?(enactment_server)

      assert %Schemas.Workitem{state: :completed} =
               Repo.get!(Schemas.Workitem, alternative_workitem.id)

      assert [workitem] === get_enactment_workitems(enactment_server)
    end
  end
end
