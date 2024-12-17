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
      places: [
        %Place{name: "input", colour_set: :int},
        %Place{name: "output", colour_set: :int}
      ],
      transitions: [
        build_transition!(name: "pass_through")
      ],
      arcs: [
        build_arc!(
          label: "in",
          place: "input",
          transition: "pass_through",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          label: "out",
          place: "output",
          transition: "pass_through",
          orientation: :t_to_p,
          expression: "{1, x}"
        )
      ]
    }

    [cpnet: cpnet]
  end

  test "works", %{cpnet: cpnet} do
    assert %{transitions: [transition]} = SetActionOutputs.run(cpnet)

    assert [] === get_in(transition, [Access.key(:action), Access.key(:outputs)])
  end

  test "sets outputs", %{cpnet: cpnet} do
    %ColouredPetriNet{
      arcs: [
        %Arc{orientation: :p_to_t} = input_arc,
        %Arc{orientation: :t_to_p}
      ]
    } = cpnet

    cpnet =
      Map.put(cpnet, :arcs, [
        input_arc,
        build_arc!(
          label: "out",
          place: "output",
          transition: "pass_through",
          orientation: :t_to_p,
          expression: "{x, y}"
        )
      ])

    assert %{transitions: [transition]} = SetActionOutputs.run(cpnet)

    assert [:y] === get_in(transition, [Access.key(:action), Access.key(:outputs)])
  end
end
