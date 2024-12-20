defmodule ColouredFlow.Validators.Definition.TerminationCriteriaValidatorTest do
  use ExUnit.Case, async: true

  use ColouredFlow.DefinitionHelpers
  import ColouredFlow.Notation

  alias ColouredFlow.Validators.Definition.TerminationCriteriaValidator
  alias ColouredFlow.Validators.Exceptions.InvalidTerminationCriteriaError

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
          expression: "{1, x}"
        )
      ],
      variables: [
        %Variable{name: :x, colour_set: :int}
      ],
      constants: [
        val(n :: int() = 2)
      ],
      termination_criteria: %TerminationCriteria{
        markings: %TerminationCriteria.Markings{
          expression:
            Expression.build!("""
            integer = 1

            match?(%{"output" => output_ms} when multi_set_coefficient(output_ms, integer) > 0, markings)
            """)
        }
      }
    }

    [cpnet: cpnet]
  end

  test "works", %{cpnet: cpnet} do
    assert {:ok, _cpnet} = TerminationCriteriaValidator.validate(cpnet)

    cpnet = update_markings_criterion(cpnet, nil)
    assert {:ok, _cpnet} = TerminationCriteriaValidator.validate(cpnet)
  end

  test "works for referring to constants", %{cpnet: cpnet} do
    cpnet =
      update_markings_criterion(cpnet, """
      match?(%{"output" => output_ms} when multi_set_coefficient(output_ms, 1) > n, markings)
      """)

    assert {:ok, _cpnet} = TerminationCriteriaValidator.validate(cpnet)
  end

  test "unknown_variable error", %{cpnet: cpnet} do
    cpnet =
      update_markings_criterion(cpnet, """
      match?(%{"output" => output_ms} when multi_set_coefficient(output_ms, 1) > m, markings)
      """)

    assert {:error, %InvalidTerminationCriteriaError{reason: :unknown_vars}} =
             TerminationCriteriaValidator.validate(cpnet)
  end

  defp update_markings_criterion(%ColouredPetriNet{} = cpnet, nil) do
    put_in(
      cpnet,
      [Access.key(:termination_criteria), Access.key(:markings)],
      nil
    )
  end

  defp update_markings_criterion(%ColouredPetriNet{} = cpnet, expression) do
    put_in(
      cpnet,
      [Access.key(:termination_criteria), Access.key(:markings)],
      %TerminationCriteria.Markings{expression: Expression.build!(expression)}
    )
  end
end
