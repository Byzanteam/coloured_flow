defmodule ColouredFlow.Definition.PresentationTest do
  use ExUnit.Case, async: true
  use ColouredFlow.DefinitionHelpers

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Presentation

  import ColouredFlow.CpnetBuilder

  describe "to_mermaid" do
    test "works" do
      cpnet = build_cpnet(:simple_sequence)

      assert_mermaid(
        cpnet,
        """
        flowchart TB
          %% colset int() :: integer()

          %% places
          input((input<br>:int:))
          output((output<br>:int:))

          %% transitions
          pass_through[pass_through]

          %% arcs
          input -->|"in"| pass_through
          pass_through -->|"out"| output
        """
      )
    end

    test "works for complex cpnet" do
      cpnet = build_cpnet(:transmission_protocol)

      assert_mermaid(
        cpnet,
        """
        flowchart TB
          %% colset bool() :: boolean()
          %% colset data() :: binary()
          %% colset no() :: integer()
          %% colset no_data() :: {integer(), binary()}

          %% places
          a((a<br>:no_data:))
          b((b<br>:no_data:))
          c((c<br>:no:))
          d((d<br>:no:))
          data_recevied((data_recevied<br>:data:))
          next_rec((next_rec<br>:no:))
          next_send((next_send<br>:no:))
          packets_to_send((packets_to_send<br>:no_data:))

          %% transitions
          receive_ack[receive_ack]
          receive_packet[receive_packet]
          send_packet[send_packet]
          transmit_ack[transmit_ack]
          transmit_packet[transmit_packet]

          %% arcs
          a -->|"bind {1, {n, d}}"| transmit_packet
          send_packet -->|"{1, {n, d}}"| a
          b -->|"bind {1, {n, d}}"| receive_packet
          transmit_packet -->|"if success, do: {1, {n, d}}, else: {0, {n, d}}"| b
          c -->|"bind {1, n}"| transmit_ack
          receive_packet -->|"if n == k, do: {1, k + 1}, else: {1, k}"| c
          d -->|"bind {1, n}"| receive_ack
          transmit_ack -->|"if success, do: {1, n}, else: {0, n}"| d
          data_recevied -->|"bind {1, data}"| receive_packet
          receive_packet -->|"if n == k, do: {1, data <> d}, else: {1, data}"| data_recevied
          next_rec -->|"bind {1, k}"| receive_packet
          receive_packet -->|"if n == k, do: {1, k + 1}, else: {1, k}"| next_rec
          next_send -->|"bind {1, k}"| receive_ack
          next_send -->|"bind {1, {1, n}}"| send_packet
          receive_ack -->|"{1, n}"| next_send
          send_packet -->|"{1, {1, n}}"| next_send
          packets_to_send -->|"bind {1, {n, d}}"| send_packet
          send_packet -->|"{1, {n, d}}"| packets_to_send
        """
      )
    end

    test "prefixes every continuation line of multi-line composite descrs with %%" do
      # `Macro.to_string` breaks long unions (enums) across lines using `|` as
      # the separator. List ordering is preserved, so the output is
      # deterministic — making an exact-match assertion possible.
      cpnet = %ColouredPetriNet{
        colour_sets: [
          %ColourSet{
            name: :color,
            type:
              {:enum,
               [
                 :alpha,
                 :bravo,
                 :charlie,
                 :delta,
                 :echo,
                 :foxtrot,
                 :golf,
                 :hotel,
                 :india,
                 :juliet,
                 :kilo,
                 :lima,
                 :mike,
                 :november
               ]}
          }
        ],
        places: [%Place{name: "input", colour_set: :color}],
        transitions: [build_transition!(name: "pass_through")],
        arcs: [
          build_arc!(
            label: "in",
            place: "input",
            transition: "pass_through",
            orientation: :p_to_t,
            expression: "bind {1, x}"
          )
        ],
        variables: [%ColouredFlow.Definition.Variable{name: :x, colour_set: :color}]
      }

      assert_mermaid(cpnet, """
      flowchart TB
        %% colset color() :: :alpha
        %% | :bravo
        %% | :charlie
        %% | :delta
        %% | :echo
        %% | :foxtrot
        %% | :golf
        %% | :hotel
        %% | :india
        %% | :juliet
        %% | :kilo
        %% | :lima
        %% | :mike
        %% | :november

        %% places
        input((input<br>:color:))

        %% transitions
        pass_through[pass_through]

        %% arcs
        input -->|"in"| pass_through
      """)
    end
  end

  defp assert_mermaid(cpnet, expected) do
    assert expected === Presentation.to_mermaid(cpnet)
  end
end
