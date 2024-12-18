defmodule ColouredFlow.Validators.Definition.StructureValidatorTest do
  use ExUnit.Case, async: true

  use ColouredFlow.DefinitionHelpers
  import ColouredFlow.Notation

  alias ColouredFlow.Validators.Definition.StructureValidator
  alias ColouredFlow.Validators.Exceptions.InvalidStructureError

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
    assert {:ok, _cpnet} = StructureValidator.validate(cpnet)
  end

  test "empty_nodes error", %{cpnet: cpnet} do
    cpnet = %ColouredPetriNet{
      cpnet
      | places: [],
        transitions: []
    }

    assert {:error, %InvalidStructureError{reason: :empty_nodes}} =
             StructureValidator.validate(cpnet)
  end

  test "missing_nodes error", %{cpnet: cpnet} do
    cpnet = %ColouredPetriNet{
      cpnet
      | places: [
          %Place{name: "input", colour_set: :int}
        ],
        transitions: []
    }

    assert {:error, %InvalidStructureError{reason: :missing_nodes} = exception} =
             StructureValidator.validate(cpnet)

    assert Exception.message(exception) =~ ~r/output/
    assert Exception.message(exception) =~ ~r/pass_through/
  end

  test "dangling_nodes error", %{cpnet: cpnet} do
    cpnet = %ColouredPetriNet{
      cpnet
      | arcs: []
    }

    assert {:error, %InvalidStructureError{reason: :dangling_nodes} = exception} =
             StructureValidator.validate(cpnet)

    assert Exception.message(exception) =~ ~r/output/
    assert Exception.message(exception) =~ ~r/pass_through/
  end

  test "duplicate_arcs error", %{cpnet: cpnet} do
    cpnet = %ColouredPetriNet{
      cpnet
      | arcs: cpnet.arcs ++ cpnet.arcs
    }

    assert {:error, %InvalidStructureError{reason: :duplicate_arcs} = exception} =
             StructureValidator.validate(cpnet)

    assert Exception.message(exception) =~ ~r/incoming-arc/
    refute Exception.message(exception) =~ ~r/outgoing-arc/
  end
end
