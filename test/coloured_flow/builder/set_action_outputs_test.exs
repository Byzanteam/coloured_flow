defmodule ColouredFlow.Builder.SetActionOutputsTest do
  use ExUnit.Case, async: true

  import ColouredFlow.Builder.DefinitionHelper
  import ColouredFlow.Notation

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place

  alias ColouredFlow.Builder.SetActionOutputs

  setup do
    cpnet = %ColouredPetriNet{
      colour_sets: [
        colset(int :: integer())
      ],
      variables: [
        var(x :: int())
      ],
      constants: [
        val(zero :: int() = 0)
      ],
      places: [
        %Place{name: "input", colour_set: :int},
        %Place{name: "intermediate", colour_set: :int},
        %Place{name: "output", colour_set: :int}
      ],
      transitions: [
        build_transition!(name: "pass_through_1"),
        build_transition!(name: "pass_through_2")
      ],
      arcs: [
        build_arc!(
          place: "input",
          transition: "pass_through_1",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          place: "intermediate",
          transition: "pass_through_1",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          place: "intermediate",
          transition: "pass_through_2",
          orientation: :p_to_t,
          expression: "bind {1, zero}"
        ),
        build_arc!(
          place: "output",
          transition: "pass_through_2",
          orientation: :t_to_p,
          expression: "{1, x}"
        )
      ]
    }

    [cpnet: cpnet]
  end

  test "works", %{cpnet: cpnet} do
    assert %{transitions: [transition_1, transition_2]} = SetActionOutputs.run(cpnet)

    assert [] === get_in(transition_1, [Access.key(:action), Access.key(:outputs)])
    assert [:x] === get_in(transition_2, [Access.key(:action), Access.key(:outputs)])
  end

  test "sets outputs", %{cpnet: cpnet} do
    %ColouredPetriNet{
      arcs: [
        %Arc{orientation: :p_to_t} = input_arc,
        %Arc{orientation: :t_to_p}
        | rest_arcs
      ]
    } = cpnet

    cpnet =
      Map.put(cpnet, :arcs, [
        input_arc,
        build_arc!(
          place: "intermediate",
          transition: "pass_through_1",
          orientation: :t_to_p,
          expression: "{x, y}"
        )
        | rest_arcs
      ])

    assert %{transitions: [transition | _rest]} = SetActionOutputs.run(cpnet)

    assert [:y] === get_in(transition, [Access.key(:action), Access.key(:outputs)])
  end

  test "does not add constants into outputs", %{cpnet: cpnet} do
    %ColouredPetriNet{
      arcs: [
        %Arc{orientation: :p_to_t} = input_arc,
        %Arc{orientation: :t_to_p}
        | rest_arcs
      ]
    } = cpnet

    cpnet =
      Map.put(cpnet, :arcs, [
        input_arc,
        build_arc!(
          place: "intermediate",
          transition: "pass_through_1",
          orientation: :t_to_p,
          expression: "{zero, y}"
        )
        | rest_arcs
      ])

    assert %{transitions: [transition | _rest]} = SetActionOutputs.run(cpnet)

    assert [:y] === get_in(transition, [Access.key(:action), Access.key(:outputs)])
  end
end
