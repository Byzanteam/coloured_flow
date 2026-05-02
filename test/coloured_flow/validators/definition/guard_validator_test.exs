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

  describe "per-transition guard scope" do
    setup do
      # Two transitions, each with its own incoming arc binding a different
      # variable. The guard scope must be evaluated per-transition rather than
      # over the union of all bindings across the net.
      cpnet = %ColouredPetriNet{
        colour_sets: [
          colset(int() :: integer())
        ],
        places: [
          %Place{name: "in_a", colour_set: :int},
          %Place{name: "in_b", colour_set: :int},
          %Place{name: "out_a", colour_set: :int},
          %Place{name: "out_b", colour_set: :int}
        ],
        transitions: [
          build_transition!(name: "t1", guard: "true"),
          build_transition!(name: "t2", guard: "true")
        ],
        arcs: [
          build_arc!(
            place: "in_a",
            transition: "t1",
            orientation: :p_to_t,
            expression: "bind {1, x}"
          ),
          build_arc!(
            place: "out_a",
            transition: "t1",
            orientation: :t_to_p,
            expression: "{1, x}"
          ),
          build_arc!(
            place: "in_b",
            transition: "t2",
            orientation: :p_to_t,
            expression: "bind {1, y}"
          ),
          build_arc!(
            place: "out_b",
            transition: "t2",
            orientation: :t_to_p,
            expression: "{1, y}"
          )
        ],
        variables: [
          %Variable{name: :x, colour_set: :int},
          %Variable{name: :y, colour_set: :int}
        ]
      }

      [cpnet: cpnet]
    end

    test "fails when t1's guard references a var bound only by t2's incoming arc",
         %{cpnet: cpnet} do
      cpnet = put_t1_guard(cpnet, "y > 0")

      assert {:error, %InvalidGuardError{reason: :unbound_vars}} =
               GuardValidator.validate(cpnet)
    end

    test "passes when t1's guard references a var bound by t1's own incoming arc",
         %{cpnet: cpnet} do
      cpnet = put_t1_guard(cpnet, "x > 0")

      assert {:ok, _cpnet} = GuardValidator.validate(cpnet)
    end

    defp put_t1_guard(%ColouredPetriNet{transitions: [_t1, t2]} = cpnet, guard) do
      %ColouredPetriNet{
        cpnet
        | transitions: [
            build_transition!(name: "t1", guard: guard),
            t2
          ]
      }
    end
  end
end
