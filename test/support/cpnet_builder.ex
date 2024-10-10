defmodule ColouredFlow.CpnetBuilder do
  use ColouredFlow.DefinitionHelpers

  import ColouredFlow.Notation.Colset

  @spec build_cpnet(name :: atom()) :: ColouredPetriNet.t()
  def build_cpnet(name)

  # ```mermaid
  # flowchart TB
  #   %% colset int() :: integer()
  #
  #   i((input))
  #   o((output))
  #
  #   pt[pass_through]
  #
  #   i --{1,x}--> pt --{1,x}--> o
  # ```
  def build_cpnet(:simple_sequence) do
    %ColouredPetriNet{
      colour_sets: [
        colset(int() :: integer())
      ],
      places: [
        %Place{name: "input", colour_set: :int},
        %Place{name: "output", colour_set: :int}
      ],
      transitions: [
        %Transition{name: "pass_through", guard: nil}
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
      ],
      variables: [
        %Variable{name: :x, colour_set: :int}
      ]
    }
  end

  # ```mermaid
  # flowchart TB
  #   %% colset int() :: integer()
  #
  #   i((input))
  #   p((place))
  #   o1((output_1))
  #   o2((output_2))
  #
  #   pt[pass_through]
  #   dc1[deferred_choice_1]
  #   dc2[deferred_choice_2]
  #
  #   i --{1,x}--> pt
  #   pt --{1,x}--> p
  #   p --{1,x}--> dc1 & dc2
  #   dc1 --{1,x}--> o1
  #   dc2 --{1,x}--> o2
  # ```
  def build_cpnet(:deferred_choice) do
    %ColouredPetriNet{
      colour_sets: [
        colset(int() :: integer())
      ],
      places: [
        %Place{name: "input", colour_set: :int},
        %Place{name: "place", colour_set: :int},
        %Place{name: "output_1", colour_set: :int},
        %Place{name: "output_2", colour_set: :int}
      ],
      transitions: [
        %Transition{name: "pass_through", guard: nil},
        %Transition{name: "deferred_choice_1", guard: nil},
        %Transition{name: "deferred_choice_2", guard: nil}
      ],
      arcs: [
        build_arc!(
          transition: "pass_through",
          place: "input",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "pass_through",
          place: "place",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "deferred_choice_1",
          place: "place",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "deferred_choice_2",
          place: "place",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "deferred_choice_1",
          place: "output_1",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "deferred_choice_2",
          place: "output_2",
          orientation: :t_to_p,
          expression: "{1, x}"
        )
      ],
      variables: [
        %Variable{name: :x, colour_set: :int}
      ]
    }
  end

  # ```mermaid
  # flowchart TB
  #   %% colset int() :: integer()
  #
  #   i((input))
  #   p1((place_1))
  #   p2((place_2))
  #   o1((output_1))
  #   o2((output_2))
  #
  #   ps[parallel_split]
  #   pt1[pass_through_1]
  #   pt2[pass_through_2]
  #
  #   i --{1,x}--> ps
  #   ps --{1,x}--> p1 & p2
  #   p1 --{1,x}--> pt1
  #   p2 --{1,x}--> pt2
  #   pt1 --{1,x}--> o1
  #   pt2 --{1,x}--> o2
  # ```
  def build_cpnet(:parallel_split) do
    %ColouredPetriNet{
      colour_sets: [
        colset(int() :: integer())
      ],
      places: [
        %Place{name: "input", colour_set: :int},
        %Place{name: "place_1", colour_set: :int},
        %Place{name: "place_2", colour_set: :int},
        %Place{name: "output_1", colour_set: :int},
        %Place{name: "output_2", colour_set: :int}
      ],
      transitions: [
        %Transition{name: "parallel_split", guard: nil},
        %Transition{name: "pass_through_1", guard: nil},
        %Transition{name: "pass_through_2", guard: nil}
      ],
      arcs: [
        build_arc!(
          transition: "parallel_split",
          place: "input",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "parallel_split",
          place: "place_1",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "parallel_split",
          place: "place_2",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "pass_through_1",
          place: "place_1",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "pass_through_2",
          place: "place_2",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "pass_through_1",
          place: "output_1",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "pass_through_2",
          place: "output_2",
          orientation: :t_to_p,
          expression: "{1, x}"
        )
      ],
      variables: [
        %Variable{name: :x, colour_set: :int}
      ]
    }
  end

  # ```mermaid
  # flowchart TB
  #   %% colset int() :: integer()
  #
  #   i1((input1))
  #   i2((input2))
  #   i3((input3))
  #   o((output))
  #
  #   join[And Join]
  #
  #   i1 & i2 & i3 --{1,x}--> join --{1,x}--> o
  # ```
  def build_cpnet(:generalized_and_join) do
    %ColouredPetriNet{
      colour_sets: [
        colset(int() :: integer())
      ],
      places: [
        %Place{name: "input1", colour_set: :int},
        %Place{name: "input2", colour_set: :int},
        %Place{name: "input3", colour_set: :int},
        %Place{name: "output", colour_set: :int}
      ],
      transitions: [
        %Transition{name: "and_join", guard: nil}
      ],
      arcs:
        build_transition_arcs!("and_join", [
          [
            label: "input1",
            place: "input1",
            orientation: :p_to_t,
            expression: "bind {1, x}"
          ],
          [
            label: "input2",
            place: "input2",
            orientation: :p_to_t,
            expression: "bind {1, x}"
          ],
          [
            label: "input3",
            place: "input3",
            orientation: :p_to_t,
            expression: "bind {1, x}"
          ],
          [
            label: "output",
            place: "output",
            orientation: :t_to_p,
            expression: "{1, x}"
          ]
        ]),
      variables: [
        %Variable{name: :x, colour_set: :int}
      ]
    }
  end

  # ```mermaid
  # flowchart TB
  #   %% colset int() :: integer()
  #
  #   i((input))
  #   m((merge))
  #   o((output))
  #
  #   b1[branch_1]
  #   b2[branch_2]
  #   tm[thread_merge]
  #
  #   i --{1,x}--> b1
  #   i --{2,x}--> b2
  #   b1 & b2 --{1,x}--> m
  #   m --{2,1}--> tm
  #   tm --{1,1}--> o
  # ```

  def build_cpnet(:thread_merge) do
    %ColouredPetriNet{
      colour_sets: [
        colset(int() :: integer())
      ],
      places: [
        %Place{name: "input", colour_set: :int},
        %Place{name: "merge", colour_set: :int},
        %Place{name: "output", colour_set: :int}
      ],
      transitions: [
        %Transition{name: "branch_1", guard: nil},
        %Transition{name: "branch_2", guard: nil},
        %Transition{name: "thread_merge", guard: nil}
      ],
      arcs: [
        build_arc!(
          transition: "branch_1",
          place: "input",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "branch_2",
          place: "input",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "branch_1",
          place: "merge",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "branch_2",
          place: "merge",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "thread_merge",
          place: "merge",
          orientation: :p_to_t,
          expression: "bind {2, 1}"
        ),
        build_arc!(
          transition: "thread_merge",
          place: "output",
          orientation: :t_to_p,
          expression: "{1, 1}"
        )
      ],
      variables: [
        %Variable{name: :x, colour_set: :int}
      ]
    }
  end

  # from Coloured Petri Nets.pdf, p. 80, Fig 4.1.
  def build_cpnet(:transmission_protocol) do
    %ColouredPetriNet{
      colour_sets: [
        colset(no() :: integer()),
        colset(data() :: binary()),
        colset(no_data() :: {integer(), binary()}),
        colset(bool() :: boolean())
      ],
      variables: [
        %Variable{name: :n, colour_set: :no},
        %Variable{name: :k, colour_set: :no},
        %Variable{name: :d, colour_set: :data},
        %Variable{name: :data, colour_set: :data},
        %Variable{name: :success, colour_set: :bool}
      ],
      places: [
        %Place{name: "packets_to_send", colour_set: :no_data},
        %Place{name: "a", colour_set: :no_data},
        %Place{name: "b", colour_set: :no_data},
        %Place{name: "data_recevied", colour_set: :data},
        %Place{name: "next_rec", colour_set: :no},
        %Place{name: "c", colour_set: :no},
        %Place{name: "d", colour_set: :no},
        %Place{name: "next_send", colour_set: :no}
      ],
      transitions: [
        %Transition{name: "send_packet"},
        %Transition{name: "transmit_packet"},
        %Transition{name: "receive_packet"},
        %Transition{name: "transmit_ack"},
        %Transition{name: "receive_ack"}
      ],
      arcs:
        List.flatten([
          # arcs are grouped by transitions, ordered by:
          # - the in or out orientation
          # - the position: top, right, bottom, left
          build_transition_arcs!("send_packet", [
            [
              place: "packets_to_send",
              orientation: :p_to_t,
              expression: """
              bind {1, {n, d}}
              """
            ],
            [
              place: "next_send",
              orientation: :p_to_t,
              expression: "bind {1, {1, n}}"
            ],
            [
              place: "packets_to_send",
              orientation: :t_to_p,
              expression: "{1, {n, d}}"
            ],
            [
              place: "a",
              orientation: :t_to_p,
              expression: "{1, {n, d}}"
            ],
            [
              place: "next_send",
              orientation: :t_to_p,
              expression: "{1, {1, n}}"
            ]
          ]),
          build_transition_arcs!("transmit_packet", [
            [
              place: "a",
              orientation: :p_to_t,
              expression: "bind {1, {n, d}}"
            ],
            [
              place: "b",
              orientation: :t_to_p,
              expression: "if success do: {1, {n, d}}, else: {0, {n, d}}"
            ]
          ]),
          build_transition_arcs!("receive_packet", [
            [
              place: "b",
              orientation: :p_to_t,
              expression: "bind {1, {n, d}}"
            ],
            [
              place: "data_recevied",
              orientation: :p_to_t,
              expression: "bind {1, data}"
            ],
            [
              place: "next_rec",
              orientation: :p_to_t,
              expression: "bind {1, k}"
            ],
            [
              place: "data_recevied",
              orientation: :t_to_p,
              expression: "if n == k do: {1, data <> d}, else: {1, data}"
            ],
            [
              place: "c",
              orientation: :t_to_p,
              expression: "if n == k, do: {1, k + 1}, else: {1, k}"
            ],
            [
              place: "next_rec",
              orientation: :t_to_p,
              expression: "if n == k, do: {1, k + 1}, else: {1, k}"
            ]
          ]),
          build_transition_arcs!("transmit_ack", [
            [
              place: "c",
              orientation: :p_to_t,
              expression: "bind {1, n}"
            ],
            [
              place: "d",
              orientation: :t_to_p,
              expression: "if success do: {1, n}, else: {0, n}"
            ]
          ]),
          build_transition_arcs!("receive_ack", [
            [
              place: "next_send",
              orientation: :p_to_t,
              expression: "bind {1, k}"
            ],
            [
              place: "d",
              orientation: :p_to_t,
              expression: "bind {1, n}"
            ],
            [
              place: "next_send",
              orientation: :t_to_p,
              expression: "{1, n}"
            ]
          ])
        ])
    }
  end

  @spec update_arc!(
          ColouredPetriNet.t(),
          {
            orientation :: Arc.orientation(),
            transition :: Transition.name(),
            place :: Place.name()
          },
          label: Arc.label(),
          expression: binary()
        ) :: ColouredPetriNet.t()
  def update_arc!(%ColouredPetriNet{} = cpnet, {orientation, transition, place}, params) do
    Map.update!(cpnet, :arcs, fn arcs ->
      arcs
      |> Enum.map_reduce(false, fn
        %Arc{orientation: ^orientation, transition: ^transition, place: ^place}, _acc ->
          arc =
            build_arc!(
              Keyword.merge(
                [orientation: orientation, transition: transition, place: place],
                params
              )
            )

          {arc, true}

        other, acc ->
          {other, acc}
      end)
      |> case do
        {arcs, true} -> arcs
        {_arcs, false} -> raise "Arc not found"
      end
    end)
  end
end
