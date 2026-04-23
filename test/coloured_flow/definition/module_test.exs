defmodule ColouredFlow.Definition.ModuleTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.PortPlace

  describe "all_places/1" do
    test "returns both port places and internal places" do
      module = %Module{
        name: "test_module",
        port_places: [
          %PortPlace{name: "port1", colour_set: :unit, port_type: :input},
          %PortPlace{name: "port2", colour_set: :unit, port_type: :output}
        ],
        places: [
          %Place{name: "internal1", colour_set: :unit},
          %Place{name: "internal2", colour_set: :unit}
        ]
      }

      all_places = Module.all_places(module)

      assert length(all_places) == 4
      assert Enum.any?(all_places, &(&1.name == "port1"))
      assert Enum.any?(all_places, &(&1.name == "port2"))
      assert Enum.any?(all_places, &(&1.name == "internal1"))
      assert Enum.any?(all_places, &(&1.name == "internal2"))
    end
  end

  describe "get_port_place/2" do
    test "returns the port place with the given name" do
      module = %Module{
        name: "test_module",
        port_places: [
          %PortPlace{name: "input", colour_set: :unit, port_type: :input},
          %PortPlace{name: "output", colour_set: :unit, port_type: :output}
        ]
      }

      port = Module.get_port_place(module, "input")
      assert port.name == "input"
      assert port.port_type == :input
    end

    test "returns nil when port place does not exist" do
      module = %Module{
        name: "test_module",
        port_places: []
      }

      assert Module.get_port_place(module, "nonexistent") == nil
    end
  end

  describe "input_ports/1" do
    test "returns only input and I/O ports" do
      module = %Module{
        name: "test_module",
        port_places: [
          %PortPlace{name: "in1", colour_set: :unit, port_type: :input},
          %PortPlace{name: "out1", colour_set: :unit, port_type: :output},
          %PortPlace{name: "io1", colour_set: :unit, port_type: :io},
          %PortPlace{name: "in2", colour_set: :unit, port_type: :input}
        ]
      }

      input_ports = Module.input_ports(module)

      assert length(input_ports) == 3
      assert Enum.any?(input_ports, &(&1.name == "in1"))
      assert Enum.any?(input_ports, &(&1.name == "in2"))
      assert Enum.any?(input_ports, &(&1.name == "io1"))
      refute Enum.any?(input_ports, &(&1.name == "out1"))
    end
  end

  describe "output_ports/1" do
    test "returns only output and I/O ports" do
      module = %Module{
        name: "test_module",
        port_places: [
          %PortPlace{name: "in1", colour_set: :unit, port_type: :input},
          %PortPlace{name: "out1", colour_set: :unit, port_type: :output},
          %PortPlace{name: "io1", colour_set: :unit, port_type: :io},
          %PortPlace{name: "out2", colour_set: :unit, port_type: :output}
        ]
      }

      output_ports = Module.output_ports(module)

      assert length(output_ports) == 3
      assert Enum.any?(output_ports, &(&1.name == "out1"))
      assert Enum.any?(output_ports, &(&1.name == "out2"))
      assert Enum.any?(output_ports, &(&1.name == "io1"))
      refute Enum.any?(output_ports, &(&1.name == "in1"))
    end
  end
end
