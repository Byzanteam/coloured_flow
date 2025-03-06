defmodule ColouredFlow.Runner.Enactment.IntegrationTests.ConstantsTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Enactment.BindingElement

  setup do
    use ColouredFlow.DefinitionHelpers

    import ColouredFlow.Notation.Colset
    import ColouredFlow.Notation.Val
    import ColouredFlow.Notation.Var

    # ```mermaid
    # flowchart TB
    #   %% If a number appears m times,
    #   %% we convert it to appear n times.
    #
    #   %% colset int() :: integer()
    #   %% val m :: int() = 3
    #   %% val n :: int() = 2
    #
    #   i((input))
    #   o((output))
    #
    #   f[filter]
    #
    #   i --{m,x}--> f --{n,x}--> o
    # ```
    cpnet =
      %ColouredPetriNet{
        colour_sets: [
          colset(int() :: integer())
        ],
        places: [
          %Place{name: "input", colour_set: :int},
          %Place{name: "output", colour_set: :int}
        ],
        transitions: [
          build_transition!(name: "filter", guard: "Integer.mod(x, m) === 0")
        ],
        arcs: [
          build_arc!(
            label: "in",
            place: "input",
            transition: "filter",
            orientation: :p_to_t,
            expression: "bind {m, x} when x > 5"
          ),
          build_arc!(
            label: "out",
            place: "output",
            transition: "filter",
            orientation: :t_to_p,
            expression: "{n, x}"
          )
        ],
        variables: [
          var(x :: int())
        ],
        constants: [
          val(m :: int() = 3),
          val(n :: int() = 2)
        ]
      }

    %{cpnet: cpnet}
  end

  setup :setup_flow
  setup :setup_enactment
  setup :start_enactment

  @tag initial_markings: [%Marking{place: "input", tokens: ~MS[3**6 4**9]}]
  test "works", %{enactment: enactment, enactment_server: enactment_server} do
    [
      %Enactment.Workitem{
        state: :enabled,
        binding_element: %BindingElement{
          transition: "filter",
          binding: [x: 6],
          to_consume: [
            %Marking{place: "input", tokens: ~MS[3**6]}
          ]
        }
      } = workitem_1,
      %Enactment.Workitem{
        state: :enabled,
        binding_element: %BindingElement{
          transition: "filter",
          binding: [x: 9],
          to_consume: [
            %Marking{place: "input", tokens: ~MS[3**9]}
          ]
        }
      } = workitem_2
    ] = get_enactment_workitems(enactment_server)

    workitem_1 = start_workitem(workitem_1, enactment_server)
    workitem_2 = start_workitem(workitem_2, enactment_server)

    {:ok, _workitems} =
      GenServer.call(
        enactment_server,
        {:complete_workitems, %{workitem_1.id => [], workitem_2.id => []}}
      )

    ref = Process.monitor(enactment_server)
    assert_receive {:DOWN, ^ref, :process, ^enactment_server, {:shutdown, _reason}}

    assert %Schemas.EnactmentLog{
             state: :terminated,
             termination: %Schemas.EnactmentLog.Termination{
               type: :implicit,
               message: nil
             }
           } = Repo.get_by!(Schemas.EnactmentLog, enactment_id: enactment.id)

    assert %Schemas.Enactment{
             state: :terminated,
             final_markings: [
               %Marking{place: "input", tokens: ~MS[1**9]},
               %Marking{place: "output", tokens: ~MS[2**6 2**9]}
             ]
           } = Repo.get!(Schemas.Enactment, enactment.id)
  end

  @tag initial_markings: [%Marking{place: "input", tokens: ~MS[3**3 4**6]}]
  test "works for guarded bind", %{enactment: enactment, enactment_server: enactment_server} do
    [
      %Enactment.Workitem{
        state: :enabled,
        binding_element: %BindingElement{
          transition: "filter",
          binding: [x: 6],
          to_consume: [
            %Marking{place: "input", tokens: ~MS[3**6]}
          ]
        }
      } = workitem
    ] = get_enactment_workitems(enactment_server)

    workitem = start_workitem(workitem, enactment_server)

    {:ok, _workitems} =
      GenServer.call(
        enactment_server,
        {:complete_workitems, %{workitem.id => []}}
      )

    ref = Process.monitor(enactment_server)
    assert_receive {:DOWN, ^ref, :process, ^enactment_server, {:shutdown, _reason}}

    assert %Schemas.Enactment{
             state: :terminated,
             final_markings: [
               %Marking{place: "input", tokens: ~MS[3**3 1**6]},
               %Marking{place: "output", tokens: ~MS[2**6]}
             ]
           } = Repo.get!(Schemas.Enactment, enactment.id)

    assert %Schemas.EnactmentLog{
             state: :terminated,
             termination: %Schemas.EnactmentLog.Termination{
               type: :implicit,
               message: nil
             }
           } = Repo.get_by!(Schemas.EnactmentLog, enactment_id: enactment.id)
  end
end
