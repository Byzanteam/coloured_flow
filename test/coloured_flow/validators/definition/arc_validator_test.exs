defmodule ColouredFlow.Validators.Definition.ArcValidatorTest do
  use ExUnit.Case, async: true

  use ColouredFlow.DefinitionHelpers
  import ColouredFlow.Notation

  alias ColouredFlow.Validators.Definition.ArcValidator
  alias ColouredFlow.Validators.Exceptions.InvalidArcError

  setup do
    cpnet = %ColouredPetriNet{
      colour_sets: [
        colset(int() :: integer())
      ],
      places: [
        %Place{name: "input", colour_set: :int},
        %Place{name: "output", colour_set: :int}
      ],
      transitions: [
        build_transition!(name: "pass_through", guard: "true")
      ],
      arcs: [
        build_arc!(
          label: "incoming-arc",
          place: "input",
          transition: "pass_through",
          orientation: :p_to_t,
          expression: "bind {n, x}"
        ),
        build_arc!(
          place: "output",
          transition: "pass_through",
          orientation: :t_to_p,
          expression: "{1, x}"
        )
      ],
      variables: [
        %Variable{name: :x, colour_set: :int}
      ],
      constants: [
        val(n :: int() = 2)
      ]
    }

    [cpnet: cpnet]
  end

  test "works", %{cpnet: cpnet} do
    assert {:ok, _cpnet} = ArcValidator.validate(cpnet)
  end

  test "works while outgoing_arc refers to outputs of the action", %{cpnet: cpnet} do
    cpnet = %ColouredPetriNet{
      cpnet
      | arcs: [
          build_arc!(
            label: "incoming-arc",
            place: "input",
            transition: "pass_through",
            orientation: :p_to_t,
            expression: "bind {n, x}"
          ),
          build_arc!(
            place: "output",
            transition: "pass_through",
            orientation: :t_to_p,
            expression: "{y, x}"
          )
        ],
        variables: [
          %Variable{name: :x, colour_set: :int},
          %Variable{name: :y, colour_set: :int}
        ]
    }

    action = build_action!(outputs: [:y])
    cpnet = update_action(cpnet, action)
    assert {:ok, _cpnet} = ArcValidator.validate(cpnet)
  end

  test "incoming_unbound_vars error", %{cpnet: cpnet} do
    %{arcs: [_incoming_arc, outgoing_arc]} = cpnet

    cpnet = %ColouredPetriNet{
      cpnet
      | arcs: [
          build_arc!(
            label: "incoming-arc",
            place: "input",
            transition: "pass_through",
            orientation: :p_to_t,
            expression: "bind {m, x}"
          ),
          outgoing_arc
        ]
    }

    assert {:error, %InvalidArcError{reason: :incoming_unbound_vars}} =
             ArcValidator.validate(cpnet)
  end

  test "outgoing_unbound_vars error", %{cpnet: cpnet} do
    %{arcs: [incoming_arc, _outgoing_arc]} = cpnet

    cpnet = %ColouredPetriNet{
      cpnet
      | arcs: [
          incoming_arc,
          build_arc!(
            place: "output",
            transition: "pass_through",
            orientation: :t_to_p,
            expression: "{m, x}"
          )
        ]
    }

    assert {:error, %InvalidArcError{reason: :outgoing_unbound_vars}} =
             ArcValidator.validate(cpnet)
  end

  defp update_action(%ColouredPetriNet{} = cpnet, %Action{} = action) do
    put_in(
      cpnet,
      [Access.key(:transitions), Access.at(0), Access.key(:action)],
      action
    )
  end
end
