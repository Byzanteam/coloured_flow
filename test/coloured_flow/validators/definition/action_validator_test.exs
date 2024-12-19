defmodule ColouredFlow.Validators.Definition.ActionValidatorTest do
  use ExUnit.Case, async: true

  use ColouredFlow.DefinitionHelpers
  import ColouredFlow.Notation

  alias ColouredFlow.Validators.Definition.ActionValidator
  alias ColouredFlow.Validators.Exceptions.InvalidActionError

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
        build_transition!(name: "pass_through")
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
          expression: "{y, x}"
        )
      ],
      variables: [
        %Variable{name: :x, colour_set: :int},
        %Variable{name: :y, colour_set: :int}
      ],
      constants: [
        val(n :: int() = 2)
      ]
    }

    [cpnet: cpnet]
  end

  test "works", %{cpnet: cpnet} do
    assert {:ok, _cpnet} = ActionValidator.validate(cpnet)
  end

  test "works for valid action", %{cpnet: cpnet} do
    action = build_action!(outputs: [:y])
    cpnet = update_action(cpnet, action)

    assert {:ok, _cpnet} = ActionValidator.validate(cpnet)
  end

  test "output_not_variable error", %{cpnet: cpnet} do
    action = build_action!(outputs: [:z])
    cpnet = update_action(cpnet, action)

    assert {:error, %InvalidActionError{reason: :output_not_variable}} =
             ActionValidator.validate(cpnet)
  end

  test "output_not_variable error for referring to a constant", %{cpnet: cpnet} do
    action = build_action!(outputs: [:n])
    cpnet = update_action(cpnet, action)

    assert {:error, %InvalidActionError{reason: :output_not_variable}} =
             ActionValidator.validate(cpnet)
  end

  test "bound_output error", %{cpnet: cpnet} do
    action = build_action!(outputs: [:x])
    cpnet = update_action(cpnet, action)

    assert {:error, %InvalidActionError{reason: :bound_output}} =
             ActionValidator.validate(cpnet)
  end

  defp update_action(%ColouredPetriNet{} = cpnet, %Action{} = action) do
    put_in(
      cpnet,
      [Access.key(:transitions), Access.at(0), Access.key(:action)],
      action
    )
  end
end
