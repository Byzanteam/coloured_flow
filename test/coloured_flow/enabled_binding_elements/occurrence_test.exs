defmodule ColouredFlow.EnabledBindingElements.OccurrenceTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable
  alias ColouredFlow.EnabledBindingElements.Occurrence
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking

  import ColouredFlow.MultiSet
  import ColouredFlow.Notation.Colset

  describe "occur" do
    test "works" do
      # (integer) -> [filter] -> (even)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = %Transition{name: "filter", guard: Expression.build!("Integer.mod(x, 2) == 0")}

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
            %Arc{
              name: "input",
              place: "integer",
              transition: "filter",
              orientation: :p_to_t,
              expression: Expression.build!("return {1, x}")
            },
            %Arc{
              name: "output",
              place: "even",
              transition: "filter",
              orientation: :t_to_p,
              expression: Expression.build!("return {1, x}")
            }
          ],
          variables: [
            %Variable{name: :x, colour_set: :int}
          ]
        }

      binding_element = %BindingElement{
        transition: "filter",
        binding: [x: 2],
        to_consume: [%Marking{place: "integer", tokens: ~b[2]}]
      }

      action_outputs = []

      occurrence = Occurrence.occur(binding_element, action_outputs, cpnet)

      assert [] === occurrence.free_assignments
      assert [%Marking{place: "even", tokens: ~b[1**2]}] === occurrence.to_produce
    end

    test "the literal arc expression" do
      # (a, b) -> [merge] -> (unit)
      colour_sets = [
        colset(unit() :: {})
      ]

      transition = %Transition{name: "merge", guard: nil}

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
            %Arc{
              name: "a",
              place: "a",
              transition: "merge",
              orientation: :p_to_t,
              expression: Expression.build!("return {2, {}}")
            },
            %Arc{
              name: "b",
              place: "b",
              transition: "merge",
              orientation: :p_to_t,
              expression: Expression.build!("return {1, {}}")
            },
            %Arc{
              name: "unit",
              place: "unit",
              transition: "merge",
              orientation: :t_to_p,
              expression: Expression.build!("return {1, {}}")
            }
          ],
          variables: []
        }

      binding_element =
        %BindingElement{
          transition: "merge",
          binding: [],
          to_consume: [
            %Marking{place: "a", tokens: ~b[2**{}]},
            %Marking{place: "b", tokens: ~b[{}]}
          ]
        }

      action_outputs = []

      occurrence = Occurrence.occur(binding_element, action_outputs, cpnet)

      assert [] === occurrence.free_assignments
      assert [%Marking{place: "unit", tokens: ~b[1**{}]}] === occurrence.to_produce
    end

    test "works with multiple output places" do
      # (number) -> [clone] -> (one, another)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = %Transition{name: "clone", guard: nil}

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
            %Arc{
              name: "number",
              place: "number",
              transition: transition.name,
              orientation: :p_to_t,
              expression: Expression.build!("return {1, x}")
            },
            %Arc{
              name: "one",
              place: "one",
              transition: transition.name,
              orientation: :t_to_p,
              expression: Expression.build!("return {1, x}")
            },
            %Arc{
              name: "another",
              place: "another",
              transition: transition.name,
              orientation: :t_to_p,
              expression: Expression.build!("return {1, x}")
            }
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
            %Marking{place: "number", tokens: ~b[1]}
          ]
        }

      action_outputs = []

      occurrence = Occurrence.occur(binding_element, action_outputs, cpnet)

      assert [] === occurrence.free_assignments

      assert [
               %Marking{place: "one", tokens: ~b[1]},
               %Marking{place: "another", tokens: ~b[1]}
             ] ===
               occurrence.to_produce
    end

    test "set free_assignments" do
      # (dividend, divisor) -> [div and mod] -> (quotient, modulo)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = %Transition{
        name: "div",
        guard: nil,
        action: %Action{
          inputs: [:dividend, :divisor],
          outputs: [:quotient, :modulo],
          code:
            Expression.build!("""
            {div(dividend, divisor), Integer.mod(dividend, divisor)}
            """)
        }
      }

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
            %Arc{
              name: "dividend",
              place: "dividend",
              transition: transition.name,
              orientation: :p_to_t,
              expression: Expression.build!("return {1, dividend}")
            },
            %Arc{
              name: "divisor",
              place: "divisor",
              transition: transition.name,
              orientation: :p_to_t,
              expression: Expression.build!("return {1, divisor}")
            },
            %Arc{
              name: "quotient",
              place: "quotient",
              transition: transition.name,
              orientation: :t_to_p,
              expression: Expression.build!("return {1, quotient}")
            },
            %Arc{
              name: "modulo",
              place: "modulo",
              transition: transition.name,
              orientation: :t_to_p,
              expression: Expression.build!("return {1, modulo}")
            }
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
            %Marking{place: "dividend", tokens: ~b[5]},
            %Marking{place: "divisor", tokens: ~b[2]}
          ]
        }

      action_outputs = [2, 1]

      occurrence = Occurrence.occur(binding_element, action_outputs, cpnet)

      assert [modulo: 1, quotient: 2] === sort_assignments(occurrence.free_assignments)

      assert [
               %Marking{place: "modulo", tokens: ~b[1]},
               %Marking{place: "quotient", tokens: ~b[2]}
             ] === sort_markings(occurrence.to_produce)
    end
  end

  defp sort_assignments(assignments) do
    Enum.sort_by(assignments, &elem(&1, 0))
  end

  defp sort_markings(markings) do
    Enum.sort_by(markings, & &1.place)
  end
end
