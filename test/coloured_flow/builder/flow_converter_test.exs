defmodule ColouredFlow.Builder.FlowConverterTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Builder.FlowConverter
  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition

  import ColouredFlow.Notation.Colset

  describe "flow_to_module/2" do
    test "converts a simple flow to a module with specified ports" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places: [
          %Place{name: "input", colour_set: :unit},
          %Place{name: "output", colour_set: :unit},
          %Place{name: "internal", colour_set: :unit}
        ],
        transitions: [
          %Transition{name: "process"}
        ],
        arcs: [
          %Arc{
            place: "input",
            transition: "process",
            orientation: :p_to_t,
            expression: Arc.build_expression!(:p_to_t, "bind {1, u}")
          },
          %Arc{
            place: "output",
            transition: "process",
            orientation: :t_to_p,
            expression: Arc.build_expression!(:t_to_p, "{1, u}")
          }
        ],
        variables: []
      }

      module =
        FlowConverter.flow_to_module(flow,
          name: "processor",
          port_specs: [
            {"input", :input},
            {"output", :output}
          ]
        )

      assert module.name == "processor"
      assert length(module.port_places) == 2
      assert length(module.places) == 1

      input_port = Enum.find(module.port_places, &(&1.name == "input"))
      assert input_port.port_type == :input
      assert input_port.colour_set == :unit

      output_port = Enum.find(module.port_places, &(&1.name == "output"))
      assert output_port.port_type == :output
      assert output_port.colour_set == :unit

      internal_place = Enum.find(module.places, &(&1.name == "internal"))
      assert internal_place != nil
    end

    test "preserves all flow definitions in the module" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {}), colset(int() :: integer())],
        places: [
          %Place{name: "p1", colour_set: :unit}
        ],
        transitions: [
          %Transition{name: "t1"},
          %Transition{name: "t2"}
        ],
        arcs: [
          %Arc{
            place: "p1",
            transition: "t1",
            orientation: :p_to_t,
            expression: Arc.build_expression!(:p_to_t, "bind {1, u}")
          }
        ],
        variables: [],
        constants: []
      }

      module =
        FlowConverter.flow_to_module(flow,
          name: "test_module",
          port_specs: [{"p1", :io}]
        )

      assert length(module.colour_sets) == 2
      assert length(module.transitions) == 2
      assert length(module.arcs) == 1
    end

    test "supports I/O port type" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places: [
          %Place{name: "bidirectional", colour_set: :unit}
        ],
        transitions: [],
        arcs: []
      }

      module =
        FlowConverter.flow_to_module(flow,
          name: "io_module",
          port_specs: [{"bidirectional", :io}]
        )

      port = Enum.find(module.port_places, &(&1.name == "bidirectional"))
      assert port.port_type == :io
    end

    test "raises when port spec references non-existent place" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places: [
          %Place{name: "existing", colour_set: :unit}
        ],
        transitions: [],
        arcs: []
      }

      assert_raise ArgumentError, ~r/non-existent places: nonexistent/, fn ->
        FlowConverter.flow_to_module(flow,
          name: "bad_module",
          port_specs: [{"nonexistent", :input}]
        )
      end
    end

    test "raises when port type is invalid" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places: [
          %Place{name: "p1", colour_set: :unit}
        ],
        transitions: [],
        arcs: []
      }

      assert_raise ArgumentError, ~r/Invalid port type/, fn ->
        FlowConverter.flow_to_module(flow,
          name: "bad_module",
          port_specs: [{"p1", :invalid_type}]
        )
      end
    end

    test "raises when required options are missing" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places: [],
        transitions: [],
        arcs: []
      }

      assert_raise ArgumentError, fn ->
        FlowConverter.flow_to_module(flow, [])
      end

      assert_raise ArgumentError, fn ->
        FlowConverter.flow_to_module(flow, name: "test")
      end

      assert_raise ArgumentError, fn ->
        FlowConverter.flow_to_module(flow, port_specs: [])
      end
    end

    test "raises on duplicate port specs" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places: [
          %Place{name: "p1", colour_set: :unit}
        ],
        transitions: [],
        arcs: []
      }

      assert_raise ArgumentError, ~r/Duplicate port specs/, fn ->
        FlowConverter.flow_to_module(flow,
          name: "dup_module",
          port_specs: [
            {"p1", :input},
            {"p1", :output}
          ]
        )
      end
    end
  end

  describe "flow_to_module_auto/2" do
    test "automatically detects input and output ports" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places: [
          %Place{name: "start", colour_set: :unit},
          %Place{name: "end", colour_set: :unit},
          %Place{name: "middle", colour_set: :unit}
        ],
        transitions: [
          %Transition{name: "t1"},
          %Transition{name: "t2"}
        ],
        arcs: [
          # start has no incoming arcs -> input port
          %Arc{
            place: "start",
            transition: "t1",
            orientation: :p_to_t,
            expression: Arc.build_expression!(:p_to_t, "bind {1, u}")
          },
          # middle has both incoming and outgoing -> internal
          %Arc{
            place: "middle",
            transition: "t1",
            orientation: :t_to_p,
            expression: Arc.build_expression!(:t_to_p, "{1, u}")
          },
          %Arc{
            place: "middle",
            transition: "t2",
            orientation: :p_to_t,
            expression: Arc.build_expression!(:p_to_t, "bind {1, u}")
          },
          # end has no outgoing arcs -> output port
          %Arc{
            place: "end",
            transition: "t2",
            orientation: :t_to_p,
            expression: Arc.build_expression!(:t_to_p, "{1, u}")
          }
        ],
        variables: []
      }

      module = FlowConverter.flow_to_module_auto(flow, "auto_module")

      assert module.name == "auto_module"
      assert length(module.port_places) == 2
      assert length(module.places) == 1

      port_names = Enum.map(module.port_places, & &1.name) |> MapSet.new()
      assert MapSet.member?(port_names, "start")
      assert MapSet.member?(port_names, "end")

      start_port = Enum.find(module.port_places, &(&1.name == "start"))
      assert start_port.port_type == :input

      end_port = Enum.find(module.port_places, &(&1.name == "end"))
      assert end_port.port_type == :output

      internal_place = Enum.find(module.places, &(&1.name == "middle"))
      assert internal_place != nil
    end

    test "handles flow with no clear ports" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places: [
          %Place{name: "p1", colour_set: :unit},
          %Place{name: "p2", colour_set: :unit}
        ],
        transitions: [%Transition{name: "t1"}],
        arcs: [
          %Arc{
            place: "p1",
            transition: "t1",
            orientation: :p_to_t,
            expression: Arc.build_expression!(:p_to_t, "bind {1, u}")
          },
          %Arc{
            place: "p1",
            transition: "t1",
            orientation: :t_to_p,
            expression: Arc.build_expression!(:t_to_p, "{1, u}")
          },
          %Arc{
            place: "p2",
            transition: "t1",
            orientation: :p_to_t,
            expression: Arc.build_expression!(:p_to_t, "bind {1, u}")
          },
          %Arc{
            place: "p2",
            transition: "t1",
            orientation: :t_to_p,
            expression: Arc.build_expression!(:t_to_p, "{1, u}")
          }
        ],
        variables: []
      }

      module = FlowConverter.flow_to_module_auto(flow, "no_ports_module")

      # All places have both incoming and outgoing, so no ports detected
      assert module.port_places == []
      assert length(module.places) == 2
    end
  end

  describe "validate_conversion/2" do
    test "returns :ok with no warnings for valid conversion" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places: [
          %Place{name: "p1", colour_set: :unit}
        ],
        transitions: [%Transition{name: "t1"}],
        arcs: [
          %Arc{
            place: "p1",
            transition: "t1",
            orientation: :p_to_t,
            expression: Arc.build_expression!(:p_to_t, "bind {1, u}")
          }
        ]
      }

      assert {:ok, []} =
               FlowConverter.validate_conversion(flow,
                 name: "test",
                 port_specs: [{"p1", :input}]
               )
    end

    test "returns error when name is missing" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places: [],
        transitions: [],
        arcs: []
      }

      assert {:error, errors} =
               FlowConverter.validate_conversion(flow, port_specs: [])

      assert Enum.any?(errors, &String.contains?(&1, "Missing required option: name"))
    end

    test "returns error when port_specs is missing" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places: [],
        transitions: [],
        arcs: []
      }

      assert {:error, errors} =
               FlowConverter.validate_conversion(flow, name: "test")

      assert Enum.any?(errors, &String.contains?(&1, "Missing required option: port_specs"))
    end

    test "returns error when port spec references non-existent place" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places: [
          %Place{name: "existing", colour_set: :unit}
        ],
        transitions: [],
        arcs: []
      }

      assert {:error, errors} =
               FlowConverter.validate_conversion(flow,
                 name: "test",
                 port_specs: [{"nonexistent", :input}]
               )

      assert Enum.any?(errors, &String.contains?(&1, "non-existent places"))
    end

    test "returns warning for isolated places" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places: [
          %Place{name: "connected", colour_set: :unit},
          %Place{name: "isolated", colour_set: :unit}
        ],
        transitions: [%Transition{name: "t1"}],
        arcs: [
          %Arc{
            place: "connected",
            transition: "t1",
            orientation: :p_to_t,
            expression: Arc.build_expression!(:p_to_t, "bind {1, u}")
          }
        ]
      }

      assert {:ok, warnings} =
               FlowConverter.validate_conversion(flow,
                 name: "test",
                 port_specs: [{"connected", :input}]
               )

      assert Enum.any?(warnings, &String.contains?(&1, "isolated places"))
    end

    test "returns warning when most places will be internal" do
      flow = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        places:
          Enum.map(1..10, fn i ->
            %Place{name: "p#{i}", colour_set: :unit}
          end),
        transitions: [],
        arcs: []
      }

      assert {:ok, warnings} =
               FlowConverter.validate_conversion(flow,
                 name: "test",
                 port_specs: [{"p1", :input}]
               )

      assert Enum.any?(warnings, &String.contains?(&1, "More than 80% of places will be internal"))
    end
  end
end
