defmodule ColouredFlow.ValidatorsTest do
  use ExUnit.Case, async: true

  import ColouredFlow.Builder.DefinitionHelper
  import ColouredFlow.Notation

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place

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

  test "valid", %{cpnet: cpnet} do
    assert {:ok, _cpnet} = ColouredFlow.Validators.run(cpnet)
  end

  test "invalid", %{cpnet: cpnet} do
    alias ColouredFlow.Validators.Exceptions.UniqueNameViolationError

    cpnet = %ColouredPetriNet{
      cpnet
      | places: [
          %Place{name: "input", colour_set: :int},
          %Place{name: "input", colour_set: :int}
        ]
    }

    assert {:error, %UniqueNameViolationError{scope: :place, name: "input"}} ===
             ColouredFlow.Validators.run(cpnet)
  end
end
