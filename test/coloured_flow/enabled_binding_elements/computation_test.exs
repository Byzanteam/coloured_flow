defmodule ColouredFlow.EnabledBindingElements.ComputationTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.MultiSet

  alias ColouredFlow.EnabledBindingElements.Computation

  import ColouredFlow.Notation.Colset
  import ColouredFlow.MultiSet

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

      markings = [%Marking{place: "integer", tokens: MultiSet.new([1, 1, 2])}]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               %BindingElement{
                 transition: "filter",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "integer", tokens: ~b[1]}]
               },
               %BindingElement{
                 transition: "filter",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "integer", tokens: ~b[1]}]
               },
               %BindingElement{
                 transition: "filter",
                 binding: [x: 2],
                 to_consume: [%Marking{place: "integer", tokens: ~b[2]}]
               }
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
               %BindingElement{
                 transition: "merge",
                 binding: [],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[2**{}]},
                   %Marking{place: "b", tokens: ~b[{}]}
                 ]
               }
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
              expression: Expression.build!("return {1, a}")
            },
            %Arc{
              name: "b",
              place: "b",
              transition: "a + b",
              orientation: :p_to_t,
              expression: Expression.build!("return {1, b}")
            },
            %Arc{
              name: "c",
              place: "c",
              transition: "a + b",
              orientation: :t_to_p,
              expression: Expression.build!("return {1, c}")
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
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 1, b: 4],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[1]},
                   %Marking{place: "b", tokens: ~b[4]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 1, b: 5],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[1]},
                   %Marking{place: "b", tokens: ~b[5]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 2, b: 4],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[2]},
                   %Marking{place: "b", tokens: ~b[4]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 2, b: 5],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[2]},
                   %Marking{place: "b", tokens: ~b[5]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 3, b: 4],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[3]},
                   %Marking{place: "b", tokens: ~b[4]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 3, b: 5],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[3]},
                   %Marking{place: "b", tokens: ~b[5]}
                 ]
               }
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
                  return {1, a}
                else
                  return {1, 0}
                end
                """)
            },
            %Arc{
              name: "b",
              place: "b",
              transition: "a + b",
              orientation: :p_to_t,
              expression: Expression.build!("return {1, b}")
            },
            %Arc{
              name: "c",
              place: "c",
              transition: "a + b",
              orientation: :t_to_p,
              expression: Expression.build!("return {1, c}")
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
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 0, b: -1],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[0]},
                   %Marking{place: "b", tokens: ~b[1**-1]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 0, b: 0],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[0]},
                   %Marking{place: "b", tokens: ~b[0]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 0, b: 1],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[0]},
                   %Marking{place: "b", tokens: ~b[1]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 1, b: -1],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[0]},
                   %Marking{place: "b", tokens: ~b[1**-1]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 1, b: 0],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[0]},
                   %Marking{place: "b", tokens: ~b[0]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 1, b: 1],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[1]},
                   %Marking{place: "b", tokens: ~b[1]}
                 ]
               }
             ] === ebes

      markings = [
        %Marking{place: "a", tokens: MultiSet.new([1])},
        %Marking{place: "b", tokens: MultiSet.new([-1, 0, 1])}
      ]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 1, b: 1],
                 to_consume: [
                   %Marking{place: "a", tokens: ~b[1]},
                   %Marking{place: "b", tokens: ~b[1]}
                 ]
               }
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
              expression: Expression.build!("return {n, x}")
            },
            %Arc{
              name: "counter",
              place: "counter",
              transition: "merge",
              orientation: :p_to_t,
              expression: Expression.build!("return {n, {}}")
            },
            %Arc{
              name: "number",
              place: "number",
              transition: "merge",
              orientation: :t_to_p,
              expression: Expression.build!("return {1, x}")
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
               %BindingElement{
                 transition: "merge",
                 binding: [n: 0, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~b[0**{}]},
                   %Marking{place: "numbers", tokens: ~b[0**1]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 0, x: 2],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~b[0**{}]},
                   %Marking{place: "numbers", tokens: ~b[0**2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 0, x: 3],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~b[0**{}]},
                   %Marking{place: "numbers", tokens: ~b[0**3]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~b[{}]},
                   %Marking{place: "numbers", tokens: ~b[1]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 2],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~b[{}]},
                   %Marking{place: "numbers", tokens: ~b[2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 3],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~b[{}]},
                   %Marking{place: "numbers", tokens: ~b[3]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 2, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~b[2**{}]},
                   %Marking{place: "numbers", tokens: ~b[2**1]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 2, x: 2],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~b[2**{}]},
                   %Marking{place: "numbers", tokens: ~b[2**2]}
                 ]
               }
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

      markings = [%Marking{place: "integer", tokens: MultiSet.new([1, 1, 2])}]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               %BindingElement{
                 transition: "filter",
                 binding: [x: 1],
                 to_consume: [
                   %Marking{place: "integer", tokens: ~b[1]}
                 ]
               },
               %BindingElement{
                 transition: "filter",
                 binding: [x: 1],
                 to_consume: [
                   %Marking{place: "integer", tokens: ~b[1]}
                 ]
               },
               %BindingElement{
                 transition: "filter",
                 binding: [x: 2],
                 to_consume: [
                   %Marking{place: "integer", tokens: ~b[2]}
                 ]
               }
             ] === ebes
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
              expression: Expression.build!("return {2, x}")
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

      markings = [%Marking{place: "integer", tokens: MultiSet.new([1, 1, 2])}]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               %BindingElement{
                 transition: "filter",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "integer", tokens: ~b[2**1]}]
               }
             ] === ebes
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
              expression: Expression.build!("return {x, c}")
            },
            %Arc{
              name: "counter",
              place: "counter",
              transition: "merge",
              orientation: :p_to_t,
              expression: Expression.build!("return {1, c}")
            },
            %Arc{
              name: "number",
              place: "number",
              transition: "merge",
              orientation: :t_to_p,
              expression: Expression.build!("return {1, x}")
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
               %BindingElement{
                 transition: "merge",
                 binding: [c: 2, x: 0],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~b[2]},
                   %Marking{place: "numbers", tokens: ~b[0**2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [c: 2, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~b[2]},
                   %Marking{place: "numbers", tokens: ~b[1**2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [c: 2, x: 2],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~b[2]},
                   %Marking{place: "numbers", tokens: ~b[2**2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [c: 3, x: 0],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~b[3]},
                   %Marking{place: "numbers", tokens: ~b[0**3]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [c: 3, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~b[3]},
                   %Marking{place: "numbers", tokens: ~b[1**3]}
                 ]
               }
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

      markings = [%Marking{place: "integer", tokens: MultiSet.new([-2, 0, 1, 2])}]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               %BindingElement{
                 transition: "filter",
                 binding: [x: 2],
                 to_consume: [%Marking{place: "integer", tokens: ~b[2]}]
               }
             ] === ebes
    end
  end

  defp list_bindings(transition, cpnet, markings) do
    transition
    |> Computation.list(cpnet, markings)
    |> Enum.map(fn binding_element ->
      binding = List.keysort(binding_element.binding, 0)
      to_consume = Enum.sort_by(binding_element.to_consume, & &1.place)

      %{binding_element | binding: binding, to_consume: to_consume}
    end)
    |> Enum.sort()
  end
end
