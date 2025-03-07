defmodule ColouredFlow.EnabledBindingElements.ComputationTest do
  use ExUnit.Case, async: true
  use ColouredFlow.DefinitionHelpers

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

      transition = build_transition!(name: "filter", guard: "true")

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

      markings = [%Marking{place: "integer", tokens: MultiSet.new([1, 1, 2])}]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               %BindingElement{
                 transition: "filter",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "integer", tokens: ~MS[1]}]
               },
               %BindingElement{
                 transition: "filter",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "integer", tokens: ~MS[1]}]
               },
               %BindingElement{
                 transition: "filter",
                 binding: [x: 2],
                 to_consume: [%Marking{place: "integer", tokens: ~MS[2]}]
               }
             ] === ebes
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
                   %Marking{place: "a", tokens: ~MS[2**{}]},
                   %Marking{place: "b", tokens: ~MS[{}]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [],
                 to_consume: [
                   %Marking{place: "a", tokens: ~MS[2**{}]},
                   %Marking{place: "b", tokens: ~MS[{}]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [],
                 to_consume: [
                   %Marking{place: "a", tokens: ~MS[2**{}]},
                   %Marking{place: "b", tokens: ~MS[{}]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [],
                 to_consume: [
                   %Marking{place: "a", tokens: ~MS[2**{}]},
                   %Marking{place: "b", tokens: ~MS[{}]}
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

      transition = build_transition!(name: "a + b")

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
            build_arc!(
              label: "a",
              place: "a",
              transition: "a + b",
              orientation: :p_to_t,
              expression: "bind {1, a}"
            ),
            build_arc!(
              label: "b",
              place: "b",
              transition: "a + b",
              orientation: :p_to_t,
              expression: "bind {1, b}"
            ),
            build_arc!(
              label: "c",
              place: "c",
              transition: "a + b",
              orientation: :t_to_p,
              expression: "{1, c}"
            )
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
                   %Marking{place: "a", tokens: ~MS[1]},
                   %Marking{place: "b", tokens: ~MS[4]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 1, b: 5],
                 to_consume: [
                   %Marking{place: "a", tokens: ~MS[1]},
                   %Marking{place: "b", tokens: ~MS[5]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 2, b: 4],
                 to_consume: [
                   %Marking{place: "a", tokens: ~MS[2]},
                   %Marking{place: "b", tokens: ~MS[4]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 2, b: 5],
                 to_consume: [
                   %Marking{place: "a", tokens: ~MS[2]},
                   %Marking{place: "b", tokens: ~MS[5]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 3, b: 4],
                 to_consume: [
                   %Marking{place: "a", tokens: ~MS[3]},
                   %Marking{place: "b", tokens: ~MS[4]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 3, b: 5],
                 to_consume: [
                   %Marking{place: "a", tokens: ~MS[3]},
                   %Marking{place: "b", tokens: ~MS[5]}
                 ]
               }
             ] ===
               ebes
    end

    test "works with multiple bindings on the in-coming arc" do
      # if b > 0: a + b, else: a + 0
      # (a, b) -> [a + b] -> (c)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = build_transition!(name: "a + b")

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
            build_arc!(
              label: "a",
              place: "a",
              transition: "a + b",
              orientation: :p_to_t,
              expression: """
              if b > 0 do
                bind {1, a}
              else
                bind {1, 0}
              end
              """
            ),
            build_arc!(
              label: "b",
              place: "b",
              transition: "a + b",
              orientation: :p_to_t,
              expression: "bind {1, b}"
            ),
            build_arc!(
              label: "c",
              place: "c",
              transition: "a + b",
              orientation: :t_to_p,
              expression: "{1, c}"
            )
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
                   %Marking{place: "a", tokens: ~MS[0]},
                   %Marking{place: "b", tokens: ~MS[1**-1]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 0, b: 0],
                 to_consume: [
                   %Marking{place: "a", tokens: ~MS[0]},
                   %Marking{place: "b", tokens: ~MS[0]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 0, b: 1],
                 to_consume: [
                   %Marking{place: "a", tokens: ~MS[0]},
                   %Marking{place: "b", tokens: ~MS[1]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 1, b: -1],
                 to_consume: [
                   %Marking{place: "a", tokens: ~MS[0]},
                   %Marking{place: "b", tokens: ~MS[1**-1]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 1, b: 0],
                 to_consume: [
                   %Marking{place: "a", tokens: ~MS[0]},
                   %Marking{place: "b", tokens: ~MS[0]}
                 ]
               },
               %BindingElement{
                 transition: "a + b",
                 binding: [a: 1, b: 1],
                 to_consume: [
                   %Marking{place: "a", tokens: ~MS[1]},
                   %Marking{place: "b", tokens: ~MS[1]}
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
                   %Marking{place: "a", tokens: ~MS[1]},
                   %Marking{place: "b", tokens: ~MS[1]}
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

      transition = build_transition!(name: "merge")

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
            build_arc!(
              label: "numbers",
              place: "numbers",
              transition: "merge",
              orientation: :p_to_t,
              expression: "bind {n, x}"
            ),
            build_arc!(
              label: "counter",
              place: "counter",
              transition: "merge",
              orientation: :p_to_t,
              expression: "bind {n, {}}"
            ),
            build_arc!(
              label: "number",
              place: "number",
              transition: "merge",
              orientation: :t_to_p,
              expression: "{1, x}"
            )
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
                   %Marking{place: "counter", tokens: ~MS[0**{}]},
                   %Marking{place: "numbers", tokens: ~MS[0**1]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 0, x: 2],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[0**{}]},
                   %Marking{place: "numbers", tokens: ~MS[0**2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 0, x: 3],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[0**{}]},
                   %Marking{place: "numbers", tokens: ~MS[0**3]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[{}]},
                   %Marking{place: "numbers", tokens: ~MS[1]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[{}]},
                   %Marking{place: "numbers", tokens: ~MS[1]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[{}]},
                   %Marking{place: "numbers", tokens: ~MS[1]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[{}]},
                   %Marking{place: "numbers", tokens: ~MS[1]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[{}]},
                   %Marking{place: "numbers", tokens: ~MS[1]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[{}]},
                   %Marking{place: "numbers", tokens: ~MS[1]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 2],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[{}]},
                   %Marking{place: "numbers", tokens: ~MS[2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 2],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[{}]},
                   %Marking{place: "numbers", tokens: ~MS[2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 2],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[{}]},
                   %Marking{place: "numbers", tokens: ~MS[2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 2],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[{}]},
                   %Marking{place: "numbers", tokens: ~MS[2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 3],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[{}]},
                   %Marking{place: "numbers", tokens: ~MS[3]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 1, x: 3],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[{}]},
                   %Marking{place: "numbers", tokens: ~MS[3]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 2, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[2**{}]},
                   %Marking{place: "numbers", tokens: ~MS[2**1]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [n: 2, x: 2],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[2**{}]},
                   %Marking{place: "numbers", tokens: ~MS[2**2]}
                 ]
               }
             ] === ebes
    end

    test "empty tokens on the in-coming arcs" do
      # (integer) -> [filter] -> (even)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = build_transition!(name: "filter")

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

      markings = [%Marking{place: "integer", tokens: MultiSet.new([1, 1, 2])}]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               %BindingElement{
                 transition: "filter",
                 binding: [x: 1],
                 to_consume: [
                   %Marking{place: "integer", tokens: ~MS[1]}
                 ]
               },
               %BindingElement{
                 transition: "filter",
                 binding: [x: 1],
                 to_consume: [
                   %Marking{place: "integer", tokens: ~MS[1]}
                 ]
               },
               %BindingElement{
                 transition: "filter",
                 binding: [x: 2],
                 to_consume: [
                   %Marking{place: "integer", tokens: ~MS[2]}
                 ]
               }
             ] === ebes
    end

    test "filter tokens by guards on the in-coming arcs" do
      # (integer) -> [filter] -> (even)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = build_transition!(name: "filter")

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
              expression: "bind {2, x}"
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

      markings = [%Marking{place: "integer", tokens: MultiSet.new([1, 1, 2])}]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               %BindingElement{
                 transition: "filter",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "integer", tokens: ~MS[2**1]}]
               }
             ] === ebes
    end

    test "works with multiple vars" do
      # (numbers, counter) -> [transition] -> (number)
      colour_sets = [
        colset(int() :: integer())
      ]

      transition = build_transition!(name: "merge")

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
            build_arc!(
              label: "numbers",
              place: "numbers",
              transition: "merge",
              orientation: :p_to_t,
              expression: "bind {x, c}"
            ),
            build_arc!(
              label: "counter",
              place: "counter",
              transition: "merge",
              orientation: :p_to_t,
              expression: "bind {1, c}"
            ),
            build_arc!(
              label: "number",
              place: "number",
              transition: "merge",
              orientation: :t_to_p,
              expression: "{1, x}"
            )
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
                   %Marking{place: "counter", tokens: ~MS[2]},
                   %Marking{place: "numbers", tokens: ~MS[0**2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [c: 2, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[2]},
                   %Marking{place: "numbers", tokens: ~MS[1**2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [c: 2, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[2]},
                   %Marking{place: "numbers", tokens: ~MS[1**2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [c: 2, x: 2],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[2]},
                   %Marking{place: "numbers", tokens: ~MS[2**2]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [c: 3, x: 0],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[3]},
                   %Marking{place: "numbers", tokens: ~MS[0**3]}
                 ]
               },
               %BindingElement{
                 transition: "merge",
                 binding: [c: 3, x: 1],
                 to_consume: [
                   %Marking{place: "counter", tokens: ~MS[3]},
                   %Marking{place: "numbers", tokens: ~MS[1**3]}
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

      transition =
        build_transition!(
          name: "filter",
          guard: """
          x > 0 and Integer.mod(x, 2) === 0
          """
        )

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

      markings = [%Marking{place: "integer", tokens: MultiSet.new([-2, 0, 1, 2])}]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               %BindingElement{
                 transition: "filter",
                 binding: [x: 2],
                 to_consume: [%Marking{place: "integer", tokens: ~MS[2]}]
               }
             ] === ebes
    end

    test "works with multiple vars and guarded transition for constants" do
      import ColouredFlow.Notation.Val

      # merge `batch_size` integers that are divisible by `divisor` into a single integer
      # eg. batch_size = 3, divisor = 2
      # integer: [2, 2, 2], result: [2]
      # (integer) -> [filter] -> (result)
      colour_sets = [
        colset(int() :: integer())
      ]

      constants = [
        val(batch_size :: int() = 3),
        val(divisor :: int() = 2)
      ]

      transition =
        build_transition!(
          name: "filter",
          guard: "Integer.mod(x, divisor) === 0"
        )

      cpnet =
        %ColouredPetriNet{
          colour_sets: colour_sets,
          places: [
            %Place{name: "integer", colour_set: :int},
            %Place{name: "result", colour_set: :int}
          ],
          transitions: [
            transition
          ],
          arcs: [
            build_arc!(
              place: "integer",
              transition: "filter",
              orientation: :p_to_t,
              expression: "bind {batch_size, x}"
            ),
            build_arc!(
              place: "result",
              transition: "filter",
              orientation: :t_to_p,
              expression: "{1, x}"
            )
          ],
          variables: [
            %Variable{name: :x, colour_set: :int}
          ],
          constants: constants
        }

      markings = [
        %Marking{place: "integer", tokens: MultiSet.new([2, 2, 2])}
      ]

      ebes = list_bindings(transition, cpnet, markings)

      assert [
               %BindingElement{
                 transition: "filter",
                 binding: [x: 2],
                 to_consume: [%Marking{place: "integer", tokens: ~MS[3**2]}]
               }
             ] === ebes
    end

    test "skip binding that its value is invalid" do
      # (integer) -> [filter] -> (even)
      colour_sets = [
        colset(int() :: integer()),
        colset(str() :: binary())
      ]

      transition = build_transition!(name: "filter", guard: "true")

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
            %Variable{name: :x, colour_set: :str}
          ]
        }

      markings = [%Marking{place: "integer", tokens: MultiSet.new([2])}]

      ebes = list_bindings(transition, cpnet, markings)

      assert [] === ebes
    end
  end

  defp list_bindings(transition, cpnet, markings) do
    markings = Map.new(markings, &{&1.place, &1})

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
