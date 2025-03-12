defmodule ColouredFlow.Runner.Enactment.IntegrationTests.ReuseWorkitemsTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Enactment.BindingElement

  setup do
    use ColouredFlow.DefinitionHelpers

    import ColouredFlow.Notation

    # ```mermaid
    # flowchart TB
    #   %% colset int() :: integer()
    #
    #   i((input))
    #   o((output))
    #
    #   count[count]
    #
    #   i --bind {1,{}}-->count
    #   count --{1,{}}-->i
    #   count --{1,{}}--> o
    # ```
    cpnet =
      %ColouredPetriNet{
        colour_sets: [
          colset(u() :: unit())
        ],
        places: [
          %Place{name: "input", colour_set: :u},
          %Place{name: "output", colour_set: :u}
        ],
        transitions: [
          build_transition!(name: "count")
        ],
        arcs: [
          arc(count <~ input :: "bind {1, {}}"),
          arc(count ~> input :: "{1, {}}"),
          arc(count ~> output :: "{1, {}}")
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

  describe "reuses workitems" do
    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[{}]}]
    test "works", %{enactment_server: enactment_server} do
      assert [
               %Enactment.Workitem{
                 state: :enabled,
                 binding_element: %BindingElement{
                   transition: "count",
                   binding: [],
                   to_consume: [%Marking{place: "input", tokens: ~MS[{}]}]
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
                   transition: "count",
                   binding: [],
                   to_consume: [%Marking{place: "input", tokens: ~MS[{}]}]
                 }
               } = new_workitem
             ] = get_enactment_workitems(enactment_server)

      refute new_workitem.id === workitem.id
    end
  end
end
