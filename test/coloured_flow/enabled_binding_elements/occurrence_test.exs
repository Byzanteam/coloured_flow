defmodule ColouredFlow.EnabledBindingElements.OccurrenceTest do
  use ExUnit.Case, async: true
  use ColouredFlow.DefinitionHelpers

  alias ColouredFlow.EnabledBindingElements.Occurrence
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking

  import ColouredFlow.MultiSet
  import ColouredFlow.Notation.Colset
  import ColouredFlow.Notation.Val

  describe "occur" do
    test "works" do
      # (integer) -> [filter] -> (even)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = build_transition!(name: "filter", guard: "Integer.mod(x, 2) == 0")

      cpnet =
        %ColouredPetriNet{
          colour_sets: colour_sets,
          places: [
            %Place{name: "integer", colour_set: :int},
            %Place{name: "even", colour_set: :int}
          ],
          transitions: [
            transition
          ],
          arcs: [
            build_arc!(
              label: "input",
              place: "integer",
              transition: "filter",
              orientation: :p_to_t,
              expression: "bind {1, x}"
            ),
            build_arc!(
              label: "output",
              place: "even",
              transition: "filter",
              orientation: :t_to_p,
              expression: "{1, x}"
            )
          ],
          variables: [
            %Variable{name: :x, colour_set: :int}
          ]
        }

      binding_element = %BindingElement{
        transition: "filter",
        binding: [x: 2],
        to_consume: [%Marking{place: "integer", tokens: ~MS[2]}]
      }

      free_binding = []

      {:ok, occurrence} = Occurrence.occur(binding_element, free_binding, cpnet)

      assert [] === occurrence.free_binding
      assert [%Marking{place: "even", tokens: ~MS[1**2]}] === occurrence.to_produce
    end

    test "the literal arc expression" do
      # (a, b) -> [merge] -> (unit)
      colour_sets = [
        colset(unit() :: {})
      ]

      transition = build_transition!(name: "merge")

      cpnet =
        %ColouredPetriNet{
          colour_sets: colour_sets,
          places: [
            %Place{name: "a", colour_set: :unit},
            %Place{name: "b", colour_set: :unit},
            %Place{name: "unit", colour_set: :unit}
          ],
          transitions: [
            transition
          ],
          arcs: [
            build_arc!(
              label: "a",
              place: "a",
              transition: "merge",
              orientation: :p_to_t,
              expression: "bind {2, {}}"
            ),
            build_arc!(
              label: "b",
              place: "b",
              transition: "merge",
              orientation: :p_to_t,
              expression: "bind {1, {}}"
            ),
            build_arc!(
              label: "unit",
              place: "unit",
              transition: "merge",
              orientation: :t_to_p,
              expression: "{1, {}}"
            )
          ],
          variables: []
        }

      binding_element =
        %BindingElement{
          transition: "merge",
          binding: [],
          to_consume: [
            %Marking{place: "a", tokens: ~MS[2**{}]},
            %Marking{place: "b", tokens: ~MS[{}]}
          ]
        }

      free_binding = []

      {:ok, occurrence} = Occurrence.occur(binding_element, free_binding, cpnet)

      assert [] === occurrence.free_binding
      assert [%Marking{place: "unit", tokens: ~MS[1**{}]}] === occurrence.to_produce
    end

    test "works with multiple output places" do
      # (number) -> [clone] -> (one, another)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = build_transition!(name: "clone")

      cpnet =
        %ColouredPetriNet{
          colour_sets: colour_sets,
          places: [
            %Place{name: "number", colour_set: :int},
            %Place{name: "one", colour_set: :int},
            %Place{name: "another", colour_set: :int}
          ],
          transitions: [
            transition
          ],
          arcs: [
            build_arc!(
              label: "number",
              place: "number",
              transition: transition.name,
              orientation: :p_to_t,
              expression: "bind {1, x}"
            ),
            build_arc!(
              label: "one",
              place: "one",
              transition: transition.name,
              orientation: :t_to_p,
              expression: "{1, x}"
            ),
            build_arc!(
              label: "another",
              place: "another",
              transition: transition.name,
              orientation: :t_to_p,
              expression: "{1, x}"
            )
          ],
          variables: [
            %Variable{name: :x, colour_set: :int}
          ]
        }

      binding_element =
        %BindingElement{
          transition: transition.name,
          binding: [x: 1],
          to_consume: [
            %Marking{place: "number", tokens: ~MS[1]}
          ]
        }

      free_binding = []

      {:ok, occurrence} = Occurrence.occur(binding_element, free_binding, cpnet)

      assert [] === occurrence.free_binding

      assert [
               %Marking{place: "one", tokens: ~MS[1]},
               %Marking{place: "another", tokens: ~MS[1]}
             ] ===
               occurrence.to_produce
    end

    test "set free_binding" do
      # (dividend, divisor) -> [div and mod] -> (quotient, modulo)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition =
        build_transition!(
          name: "div and mod",
          action: [
            payload: """
            quotient = div(dividend, divisor)
            modulo = Integer.mod(dividend, divisor)

            output {quotient, modulo}
            """,
            inputs: [],
            outputs: [:quotient, :modulo]
          ]
        )

      cpnet =
        %ColouredPetriNet{
          colour_sets: colour_sets,
          places: [
            %Place{name: "dividend", colour_set: :int},
            %Place{name: "divisor", colour_set: :int},
            %Place{name: "quotient", colour_set: :int},
            %Place{name: "modulo", colour_set: :int}
          ],
          transitions: [
            transition
          ],
          arcs: [
            build_arc!(
              label: "dividend",
              place: "dividend",
              transition: transition.name,
              orientation: :p_to_t,
              expression: "bind {1, dividend}"
            ),
            build_arc!(
              label: "divisor",
              place: "divisor",
              transition: transition.name,
              orientation: :p_to_t,
              expression: "bind {1, divisor}"
            ),
            build_arc!(
              label: "quotient",
              place: "quotient",
              transition: transition.name,
              orientation: :t_to_p,
              expression: "{1, quotient}"
            ),
            build_arc!(
              label: "modulo",
              place: "modulo",
              transition: transition.name,
              orientation: :t_to_p,
              expression: "{1, modulo}"
            )
          ],
          variables: [
            %Variable{name: :dividend, colour_set: :int},
            %Variable{name: :divisor, colour_set: :int},
            %Variable{name: :quotient, colour_set: :int},
            %Variable{name: :modulo, colour_set: :int}
          ]
        }

      binding_element =
        %BindingElement{
          transition: transition.name,
          binding: [dividend: 5, divisor: 2],
          to_consume: [
            %Marking{place: "dividend", tokens: ~MS[5]},
            %Marking{place: "divisor", tokens: ~MS[2]}
          ]
        }

      free_binding = [quotient: 2, modulo: 1]

      {:ok, occurrence} = Occurrence.occur(binding_element, free_binding, cpnet)

      assert [modulo: 1, quotient: 2] === sort_binding(occurrence.free_binding)

      assert [
               %Marking{place: "modulo", tokens: ~MS[1]},
               %Marking{place: "quotient", tokens: ~MS[2]}
             ] === sort_markings(occurrence.to_produce)
    end

    test "eval errors" do
      # (integer) -> [filter] -> (even)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = build_transition!(name: "filter", guard: "Integer.mod(x, 2) == 0")

      cpnet =
        %ColouredPetriNet{
          colour_sets: colour_sets,
          places: [
            %Place{name: "integer", colour_set: :int},
            %Place{name: "even", colour_set: :int}
          ],
          transitions: [
            transition
          ],
          arcs: [
            build_arc!(
              label: "input",
              place: "integer",
              transition: "filter",
              orientation: :p_to_t,
              expression: "bind {1, x}"
            ),
            build_arc!(
              label: "output",
              place: "even",
              transition: "filter",
              orientation: :t_to_p,
              expression: """
              1/0
              {1, x}
              """
            )
          ],
          variables: [
            %Variable{name: :x, colour_set: :int}
          ]
        }

      binding_element = %BindingElement{
        transition: "filter",
        binding: [x: 2],
        to_consume: [%Marking{place: "integer", tokens: ~MS[2]}]
      }

      free_binding = []

      {:error, exceptions} = Occurrence.occur(binding_element, free_binding, cpnet)

      assert [%ArithmeticError{}] = exceptions
    end

    test "colour_set_mismatch errors" do
      # (integer) -> [filter] -> (even)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = build_transition!(name: "filter", guard: "Integer.mod(x, 2) == 0")

      cpnet =
        %ColouredPetriNet{
          colour_sets: colour_sets,
          places: [
            %Place{name: "integer", colour_set: :int},
            %Place{name: "even", colour_set: :int}
          ],
          transitions: [
            transition
          ],
          arcs: [
            build_arc!(
              label: "input",
              place: "integer",
              transition: "filter",
              orientation: :p_to_t,
              expression: "bind {1, x}"
            ),
            build_arc!(
              label: "output",
              place: "even",
              transition: "filter",
              orientation: :t_to_p,
              expression: "{1, true}"
            )
          ],
          variables: [
            %Variable{name: :x, colour_set: :int}
          ]
        }

      binding_element = %BindingElement{
        transition: "filter",
        binding: [x: 2],
        to_consume: [%Marking{place: "integer", tokens: ~MS[2]}]
      }

      free_binding = []

      {:error, exceptions} = Occurrence.occur(binding_element, free_binding, cpnet)

      assert [
               %ColouredFlow.Definition.ColourSet.ColourSetMismatch{
                 colour_set: %ColouredFlow.Definition.ColourSet{name: :int, type: {:integer, []}},
                 value: true
               }
             ] = exceptions
    end

    test "works with constants" do
      # (integer) -> [filter] -> (even)
      colour_sets = [
        colset(int() :: integer())
      ]

      constants = [
        val(n :: int() = 5)
      ]

      transition = build_transition!(name: "filter", guard: "Integer.mod(x, 2) == 0")

      cpnet =
        %ColouredPetriNet{
          colour_sets: colour_sets,
          places: [
            %Place{name: "integer", colour_set: :int},
            %Place{name: "even", colour_set: :int}
          ],
          transitions: [
            transition
          ],
          arcs: [
            build_arc!(
              label: "input",
              place: "integer",
              transition: "filter",
              orientation: :p_to_t,
              expression: "bind {1, x}"
            ),
            build_arc!(
              label: "output",
              place: "even",
              transition: "filter",
              orientation: :t_to_p,
              expression: "{n, x}"
            )
          ],
          variables: [
            %Variable{name: :x, colour_set: :int}
          ],
          constants: constants
        }

      binding_element = %BindingElement{
        transition: "filter",
        binding: [x: 2],
        to_consume: [%Marking{place: "integer", tokens: ~MS[2]}]
      }

      free_binding = []

      {:ok, occurrence} = Occurrence.occur(binding_element, free_binding, cpnet)

      assert [] === occurrence.free_binding
      assert [%Marking{place: "even", tokens: ~MS[5**2]}] === occurrence.to_produce
    end
  end

  defp sort_binding(binding) do
    Enum.sort_by(binding, &elem(&1, 0))
  end

  defp sort_markings(markings) do
    Enum.sort_by(markings, & &1.place)
  end
end
