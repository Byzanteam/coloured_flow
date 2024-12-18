defmodule ColouredFlow.Validators.Definition.GuardValidatorTest do
  use ExUnit.Case, async: true

  use ColouredFlow.DefinitionHelpers
  import ColouredFlow.Notation

  alias ColouredFlow.Validators.Definition.GuardValidator
  alias ColouredFlow.Validators.Exceptions.InvalidGuardError

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
          expression: "bind {1, x}"
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
      ]
    }

    [cpnet: cpnet]
  end

  test "works", %{cpnet: cpnet} do
    assert {:ok, _cpnet} = GuardValidator.validate(cpnet)
  end

  test "works for referring to constants", %{cpnet: cpnet} do
    cpnet = %ColouredPetriNet{
      cpnet
      | transitions: [build_transition!(name: "pass_through", guard: "x > y")],
        constants: [val(y :: int() = 2)] ++ cpnet.constants
    }

    assert {:ok, _cpnet} = GuardValidator.validate(cpnet)
  end

  test "works for empty guard", %{cpnet: cpnet} do
    %{transitions: [transition]} = cpnet

    cpnet = %ColouredPetriNet{
      cpnet
      | transitions: [%Transition{transition | guard: nil}]
    }

    assert {:ok, _cpnet} = GuardValidator.validate(cpnet)
  end

  test "unbound_vars error", %{cpnet: cpnet} do
    cpnet = %ColouredPetriNet{
      cpnet
      | transitions: [build_transition!(name: "pass_through", guard: "x > y")]
    }

    assert {:error, %InvalidGuardError{reason: :unbound_vars}} = GuardValidator.validate(cpnet)
  end
end
