defmodule ColouredFlow.EnabledBindingElements.ComputationTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.MultiSet

  alias ColouredFlow.EnabledBindingElements.Computation

  import ColouredFlow.Notation.Colset

  describe "list_free/1" do
    test "works" do
      # (integer) -> [filter] -> (even)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = %Transition{name: "filter", guard: Expression.build!("true")}

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
              expression: Expression.build!("{1, x}"),
              returning: [{1, {:cpn_variable, :x}}]
            },
            %Arc{
              name: "output",
              place: "even",
              transition: "filter",
              orientation: :t_to_p,
              expression: Expression.build!("{1, x}"),
              returning: [{1, {:cpn_variable, :x}}]
            }
          ],
          variables: [
            %Variable{name: :x, colour_set: :int}
          ]
        }

      markings = [%Marking{place: "integer", tokens: MultiSet.new([1, 1, 2])}]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               [x: 1],
               [x: 1],
               [x: 2]
             ] === ebes
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
              expression: Expression.build!("{2, {}}"),
              returning: [{1, {}}]
            },
            %Arc{
              name: "b",
              place: "b",
              transition: "merge",
              orientation: :p_to_t,
              expression: Expression.build!("{1, {}}"),
              returning: [{1, {}}]
            },
            %Arc{
              name: "unit",
              place: "unit",
              transition: "merge",
              orientation: :t_to_p,
              expression: Expression.build!("{1, {}}"),
              returning: [{1, {}}]
            }
          ],
          variables: [
            %Variable{name: :n, colour_set: :int},
            %Variable{name: :x, colour_set: :int}
          ]
        }

      markings = [
        %Marking{place: "a", tokens: MultiSet.new([{}, {}, {}, {}, {}])},
        %Marking{place: "b", tokens: MultiSet.new([{}, {}])}
      ]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               []
             ] === ebes

      markings = [
        %Marking{place: "a", tokens: MultiSet.new([{}])},
        %Marking{place: "b", tokens: MultiSet.new([{}, {}])}
      ]

      ebes = list_bindings(transition, cpnet, markings)

      assert [] === ebes
    end

    test "works with guards on the in-coming arcs" do
      # (a, b) -> [a + b] -> (c)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = %Transition{name: "a + b", guard: nil}

      cpnet =
        %ColouredPetriNet{
          colour_sets: colour_sets,
          places: [
            %Place{name: "a", colour_set: :int},
            %Place{name: "b", colour_set: :int},
            %Place{name: "c", colour_set: :int}
          ],
          transitions: [
            transition
          ],
          arcs: [
            %Arc{
              name: "a",
              place: "a",
              transition: "a + b",
              orientation: :p_to_t,
              expression: Expression.build!("{1, a}"),
              returning: [{1, {:cpn_variable, :a}}]
            },
            %Arc{
              name: "b",
              place: "b",
              transition: "a + b",
              orientation: :p_to_t,
              expression: Expression.build!("{1, b}"),
              returning: [{1, {:cpn_variable, :b}}]
            },
            %Arc{
              name: "c",
              place: "c",
              transition: "a + b",
              orientation: :t_to_p,
              expression: Expression.build!("{1, c}"),
              returning: [{1, {:cpn_variable, :c}}]
            }
          ],
          variables: [
            %Variable{name: :a, colour_set: :int},
            %Variable{name: :b, colour_set: :int},
            %Variable{name: :c, colour_set: :int}
          ]
        }

      markings = [
        %Marking{place: "a", tokens: MultiSet.new([1, 2, 3])},
        %Marking{place: "b", tokens: MultiSet.new([4, 5])}
      ]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               [a: 1, b: 4],
               [a: 1, b: 5],
               [a: 2, b: 4],
               [a: 2, b: 5],
               [a: 3, b: 4],
               [a: 3, b: 5]
             ] ===
               ebes
    end

    test "works with multiple returning on the in-coming arc" do
      # if b > 0: a + b, else: a + 0
      # (a, b) -> [a + b] -> (c)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = %Transition{name: "a + b", guard: nil}

      cpnet =
        %ColouredPetriNet{
          colour_sets: colour_sets,
          places: [
            %Place{name: "a", colour_set: :int},
            %Place{name: "b", colour_set: :int},
            %Place{name: "c", colour_set: :int}
          ],
          transitions: [
            transition
          ],
          arcs: [
            %Arc{
              name: "a",
              place: "a",
              transition: "a + b",
              orientation: :p_to_t,
              expression:
                Expression.build!("""
                if b > 0 do
                  {1, a}
                else
                  {1, 0}
                end
                """),
              returning: [{1, {:cpn_variable, :a}}, {1, 0}]
            },
            %Arc{
              name: "b",
              place: "b",
              transition: "a + b",
              orientation: :p_to_t,
              expression: Expression.build!("{1, b}"),
              returning: [{1, {:cpn_variable, :b}}]
            },
            %Arc{
              name: "c",
              place: "c",
              transition: "a + b",
              orientation: :t_to_p,
              expression: Expression.build!("{1, c}"),
              returning: [{1, {:cpn_variable, :c}}]
            }
          ],
          variables: [
            %Variable{name: :a, colour_set: :int},
            %Variable{name: :b, colour_set: :int},
            %Variable{name: :c, colour_set: :int}
          ]
        }

      markings = [
        %Marking{place: "a", tokens: MultiSet.new([0, 1])},
        %Marking{place: "b", tokens: MultiSet.new([-1, 0, 1])}
      ]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               [a: 0, b: -1],
               [a: 0, b: 0],
               [a: 0, b: 1],
               [a: 1, b: -1],
               [a: 1, b: 0],
               [a: 1, b: 1]
             ] === ebes

      markings = [
        %Marking{place: "a", tokens: MultiSet.new([1])},
        %Marking{place: "b", tokens: MultiSet.new([-1, 0, 1])}
      ]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               [a: 1, b: 1]
             ] === ebes
    end

    test "the coefficient is variable and the value is literal" do
      # (numbers, counter) -> [merge] -> (number)
      colour_sets = [
        colset(int() :: integer()),
        colset(unit() :: {})
      ]

      transition = %Transition{name: "merge", guard: nil}

      cpnet =
        %ColouredPetriNet{
          colour_sets: colour_sets,
          places: [
            %Place{name: "numbers", colour_set: :int},
            %Place{name: "counter", colour_set: :unit},
            %Place{name: "number", colour_set: :int}
          ],
          transitions: [
            transition
          ],
          arcs: [
            %Arc{
              name: "numbers",
              place: "numbers",
              transition: "merge",
              orientation: :p_to_t,
              expression: Expression.build!("{n, x}"),
              returning: [{{:cpn_variable, :n}, {:cpn_variable, :x}}]
            },
            %Arc{
              name: "counter",
              place: "counter",
              transition: "merge",
              orientation: :p_to_t,
              expression: Expression.build!("{n, {}}"),
              returning: [{{:cpn_variable, :n}, {}}]
            },
            %Arc{
              name: "number",
              place: "number",
              transition: "merge",
              orientation: :t_to_p,
              expression: Expression.build!("{1, x}"),
              returning: [{1, {:cpn_variable, :x}}]
            }
          ],
          variables: [
            %Variable{name: :n, colour_set: :int},
            %Variable{name: :x, colour_set: :int}
          ]
        }

      markings = [
        %Marking{place: "numbers", tokens: MultiSet.new([1, 1, 1, 2, 2, 3])},
        %Marking{place: "counter", tokens: MultiSet.new([{}, {}])}
      ]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               [n: 0, x: 1],
               [n: 0, x: 2],
               [n: 0, x: 3],
               [n: 1, x: 1],
               [n: 1, x: 2],
               [n: 1, x: 3],
               [n: 2, x: 1],
               [n: 2, x: 2]
             ] === ebes
    end

    test "empty tokens on the in-coming arcs" do
      # (integer) -> [filter] -> (even)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = %Transition{name: "filter", guard: nil}

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
              expression: Expression.build!("{0, x}"),
              returning: [{0, {:cpn_variable, :x}}]
            },
            %Arc{
              name: "output",
              place: "even",
              transition: "filter",
              orientation: :t_to_p,
              expression: Expression.build!("{1, x}"),
              returning: [{1, {:cpn_variable, :x}}]
            }
          ],
          variables: [
            %Variable{name: :x, colour_set: :int}
          ]
        }

      markings = [%Marking{place: "integer", tokens: MultiSet.new([1, 1, 2])}]

      ebes = list_bindings(transition, cpnet, markings)

      assert [[x: 1], [x: 2]] === ebes
    end

    test "filter tokens by guards on the in-coming arcs" do
      # (integer) -> [filter] -> (even)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = %Transition{name: "filter", guard: nil}

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
              expression: Expression.build!("{2, x}"),
              returning: [{2, {:cpn_variable, :x}}]
            },
            %Arc{
              name: "output",
              place: "even",
              transition: "filter",
              orientation: :t_to_p,
              expression: Expression.build!("{1, x}"),
              returning: [{1, {:cpn_variable, :x}}]
            }
          ],
          variables: [
            %Variable{name: :x, colour_set: :int}
          ]
        }

      markings = [%Marking{place: "integer", tokens: MultiSet.new([1, 1, 2])}]

      ebes = list_bindings(transition, cpnet, markings)

      assert [[x: 1]] === ebes
    end

    test "works with multiple vars" do
      # (numbers, counter) -> [transition] -> (number)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = %Transition{name: "merge", guard: nil}

      cpnet =
        %ColouredPetriNet{
          colour_sets: colour_sets,
          places: [
            %Place{name: "numbers", colour_set: :int},
            %Place{name: "counter", colour_set: :int},
            %Place{name: "number", colour_set: :int}
          ],
          transitions: [
            transition
          ],
          arcs: [
            %Arc{
              name: "numbers",
              place: "numbers",
              transition: "merge",
              orientation: :p_to_t,
              expression: Expression.build!("{x, c}"),
              returning: [{{:cpn_variable, :x}, {:cpn_variable, :c}}]
            },
            %Arc{
              name: "counter",
              place: "counter",
              transition: "merge",
              orientation: :p_to_t,
              expression: Expression.build!("{1, c}"),
              returning: [{1, {:cpn_variable, :c}}]
            },
            %Arc{
              name: "number",
              place: "number",
              transition: "merge",
              orientation: :t_to_p,
              expression: Expression.build!("{1, x}"),
              returning: [{1, {:cpn_variable, :x}}]
            }
          ],
          variables: [
            %Variable{name: :x, colour_set: :int},
            %Variable{name: :c, colour_set: :int}
          ]
        }

      markings = [
        %Marking{place: "numbers", tokens: MultiSet.new([1, 1, 1, 2, 2, 3])},
        %Marking{place: "counter", tokens: MultiSet.new([2, 3])}
      ]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               [c: 2, x: 0],
               [c: 2, x: 1],
               [c: 2, x: 2],
               [c: 3, x: 0],
               [c: 3, x: 1]
             ] === ebes
    end

    test "works with guarded transition" do
      # filter positive even numbers
      # (integer) -> [filter] -> (even)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = %Transition{
        name: "filter",
        guard:
          Expression.build!("""
          x > 0 and Integer.mod(x, 2) === 0
          """)
      }

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
              expression: Expression.build!("{1, x}"),
              returning: [{1, {:cpn_variable, :x}}]
            },
            %Arc{
              name: "output",
              place: "even",
              transition: "filter",
              orientation: :t_to_p,
              expression: Expression.build!("{1, x}"),
              returning: [{1, {:cpn_variable, :x}}]
            }
          ],
          variables: [
            %Variable{name: :x, colour_set: :int}
          ]
        }

      markings = [%Marking{place: "integer", tokens: MultiSet.new([-2, 0, 1, 2])}]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               [x: 2]
             ] === ebes
    end
  end

  defp list_bindings(transition, cpnet, markings) do
    transition
    |> Computation.list(cpnet, markings)
    |> Enum.map(&List.keysort(&1, 0))
    |> Enum.sort()
  end
end
