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

  test "outgoing_unbound_vars error when var is bound on a different transition" do
    # Two transitions T1 and T2, each with their own input/output places.
    # T1 has an incoming arc binding `x`.
    # T2 has an outgoing arc referencing `x`, but T2's incoming arc only binds `y`.
    # In CPN semantics, variables bind only within a single transition's firing,
    # so T2's outgoing arc must NOT see `x` from T1.
    cpnet = %ColouredPetriNet{
      colour_sets: [
        colset(int() :: integer())
      ],
      places: [
        %Place{name: "p1_in", colour_set: :int},
        %Place{name: "p1_out", colour_set: :int},
        %Place{name: "p2_in", colour_set: :int},
        %Place{name: "p2_out", colour_set: :int}
      ],
      transitions: [
        build_transition!(name: "t1", guard: "true"),
        build_transition!(name: "t2", guard: "true")
      ],
      arcs: [
        # T1 binds `x` on its incoming arc.
        build_arc!(
          label: "t1-in",
          place: "p1_in",
          transition: "t1",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          label: "t1-out",
          place: "p1_out",
          transition: "t1",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        # T2 binds only `y` — no `x` is in scope here.
        build_arc!(
          label: "t2-in",
          place: "p2_in",
          transition: "t2",
          orientation: :p_to_t,
          expression: "bind {1, y}"
        ),
        # This outgoing arc references `x`, which was bound on a *different*
        # transition. Pre-fix, the validator pooled bound vars across all
        # transitions and silently accepted this; post-fix, it must reject.
        build_arc!(
          label: "t2-out",
          place: "p2_out",
          transition: "t2",
          orientation: :t_to_p,
          expression: "{1, x}"
        )
      ],
      variables: [
        %Variable{name: :x, colour_set: :int},
        %Variable{name: :y, colour_set: :int}
      ],
      constants: []
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
