# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule ColouredFlow.Factory do
  @moduledoc false

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlow.TestRepo, as: Repo

  use ExMachina.Ecto, repo: Repo

  import ColouredFlow.MultiSet, only: [sigil_b: 2]

  def flow_factory do
    %Schemas.Flow{
      id: Ecto.UUID.generate(),
      name: sequence(:flow_name, &"flow-#{&1}"),
      version: 1,
      data: fn -> %{definition: build_cpnet(:simple_sequence)} end
    }
  end

  def flow_with_cpnet(flow, flow_name) do
    Map.put(flow, :data, %{definition: build_cpnet(flow_name)})
  end

  defp build_cpnet(:simple_sequence) do
    import ColouredFlow.Notation.Colset

    use ColouredFlow.DefinitionHelpers

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

  defp build_cpnet(:transmission_protocol) do
    # from Coloured Petri Nets.pdf, p. 80, Fig 4.1.
    import ColouredFlow.Notation.Colset

    use ColouredFlow.DefinitionHelpers

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

  def enactment_factory do
    %Schemas.Enactment{
      id: Ecto.UUID.generate(),
      flow: fn -> build(:flow) end,
      data: %{initial_markings: []}
    }
  end

  def enactment_with_initial_markings(enactment, markings) when is_list(markings) do
    Map.put(enactment, :data, %{initial_markings: markings})
  end

  def occurrence_factory do
    %Schemas.Occurrence{
      id: Ecto.UUID.generate(),
      enactment: fn -> build(:enactment) end,
      step_number: sequence(:occurrence_step_number, & &1),
      data: fn ->
        %{
          occurrence: %Occurrence{
            binding_element:
              BindingElement.new(
                "pass_through",
                [x: 1],
                [%Marking{place: "integer", tokens: ~b[1]}]
              ),
            free_assignments: [],
            to_produce: [%Marking{place: "output", tokens: ~b[1**2]}]
          }
        }
      end
    }
  end

  def occurrence_with_occurrence(enactment, %Occurrence{} = occurrence) do
    Map.put(enactment, :data, %{occurrence: occurrence})
  end

  def workitem_factory do
    %Schemas.Workitem{
      id: Ecto.UUID.generate(),
      enactment: fn -> build(:enactment) end,
      state: :enabled,
      data: fn ->
        %{
          binding_element:
            BindingElement.new(
              "pass_through",
              [x: 1],
              [%Marking{place: "integer", tokens: ~b[1]}]
            )
        }
      end
    }
  end

  def workitem_with_binding_element(workitem, %BindingElement{} = binding_element) do
    Map.put(workitem, :data, %{binding_element: binding_element})
  end

  def snapshot_factory do
    %Schemas.Snapshot{
      enactment: fn -> build(:enactment) end,
      version: sequence(:snapshot_version, & &1),
      data: fn -> %{markings: []} end
    }
  end

  def snapshot_with_markings(snapshot, markings) when is_list(markings) do
    Map.put(snapshot, :data, %{markings: markings})
  end
end
