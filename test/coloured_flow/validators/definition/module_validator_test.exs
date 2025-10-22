defmodule ColouredFlow.Validators.Definition.ModuleValidatorTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.PortPlace
  alias ColouredFlow.Definition.SocketAssignment
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Validators.Definition.ModuleValidator
  alias ColouredFlow.Validators.Exceptions.InvalidModuleError

  import ColouredFlow.Notation.Colset

  describe "validate/1 with valid module" do
    test "accepts a simple valid module" do
      cpnet = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        modules: [
          %Module{
            name: "simple_module",
            port_places: [
              %PortPlace{name: "input", colour_set: :unit, port_type: :input},
              %PortPlace{name: "output", colour_set: :unit, port_type: :output}
            ],
            places: [
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
        ],
        places: [],
        transitions: [],
        arcs: []
      }

      assert {:ok, ^cpnet} = ModuleValidator.validate(cpnet)
    end
  end

  describe "validate/1 with invalid module names" do
    test "rejects duplicate module names" do
      cpnet = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        modules: [
          %Module{name: "duplicate", port_places: [], places: [], transitions: [], arcs: []},
          %Module{name: "duplicate", port_places: [], places: [], transitions: [], arcs: []}
        ],
        places: [],
        transitions: [],
        arcs: []
      }

      assert {:error, %InvalidModuleError{reason: :duplicate_module_names}} =
               ModuleValidator.validate(cpnet)
    end
  end

  describe "validate/1 with invalid port places" do
    test "rejects duplicate port place names" do
      cpnet = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        modules: [
          %Module{
            name: "test_module",
            port_places: [
              %PortPlace{name: "duplicate", colour_set: :unit, port_type: :input},
              %PortPlace{name: "duplicate", colour_set: :unit, port_type: :output}
            ],
            places: [],
            transitions: [],
            arcs: []
          }
        ],
        places: [],
        transitions: [],
        arcs: []
      }

      assert {:error, %InvalidModuleError{reason: :duplicate_port_places}} =
               ModuleValidator.validate(cpnet)
    end

    test "rejects overlapping port and internal place names" do
      cpnet = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        modules: [
          %Module{
            name: "test_module",
            port_places: [
              %PortPlace{name: "overlap", colour_set: :unit, port_type: :input}
            ],
            places: [
              %Place{name: "overlap", colour_set: :unit}
            ],
            transitions: [],
            arcs: []
          }
        ],
        places: [],
        transitions: [],
        arcs: []
      }

      assert {:error, %InvalidModuleError{reason: :overlapping_place_names}} =
               ModuleValidator.validate(cpnet)
    end
  end

  describe "validate/1 with invalid arcs" do
    test "rejects arcs referencing non-existent places" do
      cpnet = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        modules: [
          %Module{
            name: "test_module",
            port_places: [],
            places: [%Place{name: "place1", colour_set: :unit}],
            transitions: [%Transition{name: "trans1"}],
            arcs: [
              %Arc{
                place: "nonexistent",
                transition: "trans1",
                orientation: :p_to_t,
                expression: Arc.build_expression!(:p_to_t, "bind {1, u}")
              }
            ]
          }
        ],
        places: [],
        transitions: [],
        arcs: []
      }

      assert {:error, %InvalidModuleError{reason: :invalid_arc_references}} =
               ModuleValidator.validate(cpnet)
    end
  end

  describe "validate/1 with substitution transitions" do
    test "accepts valid substitution transition" do
      cpnet = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        modules: [
          %Module{
            name: "my_module",
            port_places: [
              %PortPlace{name: "port_in", colour_set: :unit, port_type: :input}
            ],
            places: [],
            transitions: [],
            arcs: []
          }
        ],
        places: [
          %Place{name: "socket_place", colour_set: :unit}
        ],
        transitions: [
          %Transition{
            name: "subst_trans",
            subst: "my_module",
            socket_assignments: [
              %SocketAssignment{socket: "socket_place", port: "port_in"}
            ]
          }
        ],
        arcs: []
      }

      assert {:ok, ^cpnet} = ModuleValidator.validate(cpnet)
    end

    test "rejects substitution transition referencing non-existent module" do
      cpnet = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        modules: [],
        places: [%Place{name: "socket_place", colour_set: :unit}],
        transitions: [
          %Transition{
            name: "subst_trans",
            subst: "nonexistent_module",
            socket_assignments: []
          }
        ],
        arcs: []
      }

      assert {:error, %InvalidModuleError{reason: :module_not_found}} =
               ModuleValidator.validate(cpnet)
    end

    test "rejects missing socket assignments" do
      cpnet = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        modules: [
          %Module{
            name: "my_module",
            port_places: [
              %PortPlace{name: "port_in", colour_set: :unit, port_type: :input},
              %PortPlace{name: "port_out", colour_set: :unit, port_type: :output}
            ],
            places: [],
            transitions: [],
            arcs: []
          }
        ],
        places: [%Place{name: "socket_place", colour_set: :unit}],
        transitions: [
          %Transition{
            name: "subst_trans",
            subst: "my_module",
            socket_assignments: [
              %SocketAssignment{socket: "socket_place", port: "port_in"}
              # Missing assignment for port_out
            ]
          }
        ],
        arcs: []
      }

      assert {:error, %InvalidModuleError{reason: :missing_socket_assignments}} =
               ModuleValidator.validate(cpnet)
    end

    test "rejects colour set mismatch between socket and port" do
      cpnet = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {}), colset(int() :: integer())],
        modules: [
          %Module{
            name: "my_module",
            port_places: [
              %PortPlace{name: "port_in", colour_set: :int, port_type: :input}
            ],
            places: [],
            transitions: [],
            arcs: []
          }
        ],
        places: [
          %Place{name: "socket_place", colour_set: :unit}
        ],
        transitions: [
          %Transition{
            name: "subst_trans",
            subst: "my_module",
            socket_assignments: [
              %SocketAssignment{socket: "socket_place", port: "port_in"}
            ]
          }
        ],
        arcs: []
      }

      assert {:error, %InvalidModuleError{reason: :colour_set_mismatch}} =
               ModuleValidator.validate(cpnet)
    end
  end

  describe "validate/1 with circular references" do
    test "detects simple circular reference" do
      cpnet = %ColouredPetriNet{
        colour_sets: [colset(unit() :: {})],
        modules: [
          %Module{
            name: "module_a",
            port_places: [],
            places: [],
            transitions: [
              %Transition{name: "call_b", subst: "module_b", socket_assignments: []}
            ],
            arcs: []
          },
          %Module{
            name: "module_b",
            port_places: [],
            places: [],
            transitions: [
              %Transition{name: "call_a", subst: "module_a", socket_assignments: []}
            ],
            arcs: []
          }
        ],
        places: [],
        transitions: [],
        arcs: []
      }

      assert {:error, %InvalidModuleError{reason: :circular_module_reference}} =
               ModuleValidator.validate(cpnet)
    end
  end
end
