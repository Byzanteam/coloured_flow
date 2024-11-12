defmodule ColouredFlow.Definition.Validators.UniqueNameValidatorTest do
  use ExUnit.Case, async: true

  use ColouredFlow.DefinitionHelpers
  import ColouredFlow.Notation.Colset

  alias ColouredFlow.Definition.Validators.Exceptions.UniqueNameViolationError
  alias ColouredFlow.Definition.Validators.UniqueNameValidator

  setup :setup_cpnet

  test "valid cpnet", %{cpnet: cpnet} do
    assert {:ok, cpnet} === UniqueNameValidator.validate(cpnet)
  end

  test ":colour_sets scope", %{cpnet: cpnet} do
    cpnet = %{
      cpnet
      | colour_sets: [
          colset(int() :: integer()),
          colset(int() :: integer())
        ]
    }

    assert {
             :error,
             %UniqueNameViolationError{
               scope: :colour_set,
               name: :int
             }
           } = UniqueNameValidator.validate(cpnet)
  end

  test ":variables_and_constants scope", %{cpnet: original_cpnet} do
    # duplicate variables
    cpnet = %{
      original_cpnet
      | variables: [
          %Variable{name: :foo, colour_set: :int},
          %Variable{name: :foo, colour_set: :int}
        ]
    }

    assert {
             :error,
             %UniqueNameViolationError{
               scope: :variable_and_constant,
               name: :foo
             }
           } = UniqueNameValidator.validate(cpnet)

    # duplicate constants
    cpnet = %{
      original_cpnet
      | constants: [
          %Constant{name: :bar, colour_set: :int, value: 1},
          %Constant{name: :bar, colour_set: :int, value: 2}
        ]
    }

    assert {
             :error,
             %UniqueNameViolationError{
               scope: :variable_and_constant,
               name: :bar
             }
           } = UniqueNameValidator.validate(cpnet)

    # duplicate variable and constant
    cpnet = %{
      original_cpnet
      | constants: [
          %Constant{name: :x, colour_set: :int, value: 2}
        ]
    }

    assert {
             :error,
             %UniqueNameViolationError{
               scope: :variable_and_constant,
               name: :x
             }
           } = UniqueNameValidator.validate(cpnet)
  end

  test ":places scope", %{cpnet: cpnet} do
    cpnet = %{
      cpnet
      | places: [
          %Place{name: "input", colour_set: :int},
          %Place{name: "input", colour_set: :int}
        ]
    }

    assert {
             :error,
             %UniqueNameViolationError{
               scope: :place,
               name: "input"
             }
           } = UniqueNameValidator.validate(cpnet)
  end

  test ":transitions scope", %{cpnet: cpnet} do
    cpnet = %{
      cpnet
      | transitions: [
          build_transition!(name: "pass_through"),
          build_transition!(name: "pass_through")
        ]
    }

    assert {
             :error,
             %UniqueNameViolationError{
               scope: :transition,
               name: "pass_through"
             }
           } = UniqueNameValidator.validate(cpnet)
  end

  defp setup_cpnet(_cxt) do
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
      ],
      variables: [
        %Variable{name: :x, colour_set: :int}
      ]
    }

    [cpnet: cpnet]
  end
end
