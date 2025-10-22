# Module Support in ColouredFlow

This document describes the module support implementation in ColouredFlow, which enables hierarchical composition and reuse in Coloured Petri Nets.

## Overview

Module support allows you to create reusable subnet definitions that can be instantiated multiple times within a workflow. This is based on the substitution transition concept from CPN theory.

## Key Concepts

### 1. Module

A `Module` represents a reusable subnet with a defined interface. It contains:

- **Port Places**: Interface points for communication with the parent net
- **Internal Places**: Places that are internal to the module
- **Transitions**: Can be regular or substitution transitions (modules can contain modules)
- **Arcs**: Connections between places and transitions
- **Colour Sets, Variables, Constants, Functions**: Supporting definitions

```elixir
%ColouredFlow.Definition.Module{
  name: "authentication",
  port_places: [
    %PortPlace{name: "credentials_in", colour_set: :credentials, port_type: :input},
    %PortPlace{name: "success_out", colour_set: :unit, port_type: :output},
    %PortPlace{name: "failure_out", colour_set: :string, port_type: :output}
  ],
  places: [
    %Place{name: "verify", colour_set: :credentials}
  ],
  transitions: [...],
  arcs: [...]
}
```

### 2. Port Places

Port places define the interface of a module. There are three types:

- **Input (`:input`)**: Receives tokens from the parent net
- **Output (`:output`)**: Sends tokens to the parent net
- **I/O (`:io`)**: Bidirectional communication

```elixir
%ColouredFlow.Definition.PortPlace{
  name: "input_data",
  colour_set: :string,
  port_type: :input
}
```

### 3. Substitution Transition

A substitution transition is a transition in the parent net that references a module. When it fires, it executes the referenced module.

```elixir
%ColouredFlow.Definition.Transition{
  name: "authenticate_user",
  subst: "authentication",  # References the module
  socket_assignments: [
    %SocketAssignment{socket: "user_creds", port: "credentials_in"},
    %SocketAssignment{socket: "auth_success", port: "success_out"},
    %SocketAssignment{socket: "auth_failure", port: "failure_out"}
  ]
}
```

### 4. Socket Assignment

Socket assignments map places in the parent net (sockets) to port places in the module. The colour sets must match.

```elixir
%ColouredFlow.Definition.SocketAssignment{
  socket: "parent_place",  # Place in parent net
  port: "module_port"      # Port place in module
}
```

## Usage Example

### Defining a Module

```elixir
import ColouredFlow.Builder.ModuleHelper
import ColouredFlow.Notation.Colset

# Define a simple authentication module
auth_module = build_module!(
  name: "authentication",
  port_places: [
    input_port("credentials", :credentials),
    output_port("success", :unit),
    output_port("failure", :string)
  ],
  places: [
    %Place{name: "validate", colour_set: :credentials}
  ],
  transitions: [
    build_transition!(name: "check_creds", action: [payload: "..."])
  ],
  arcs: [
    arc(check_creds <~ credentials :: "bind {1, creds}"),
    arc(check_creds ~> success :: "{1, {}}"),
    arc(check_creds ~> failure :: "{1, error_msg}")
  ]
)
```

### Using a Module with Substitution Transition

```elixir
%ColouredPetriNet{
  colour_sets: [
    colset(credentials() :: {username: string(), password: string()}),
    colset(unit() :: {}),
    colset(string() :: String.t())
  ],
  modules: [auth_module],
  places: [
    %Place{name: "user_input", colour_set: :credentials},
    %Place{name: "authenticated", colour_set: :unit},
    %Place{name: "auth_error", colour_set: :string}
  ],
  transitions: [
    build_substitution_transition!(
      name: "do_auth",
      subst: "authentication",
      socket_assignments: [
        socket("user_input", "credentials"),
        socket("authenticated", "success"),
        socket("auth_error", "failure")
      ]
    )
  ],
  arcs: [...]
}
```

## Validation

The `ModuleValidator` ensures:

1. **Unique Module Names**: No duplicate module names
2. **Valid Port Places**: No duplicate or overlapping port/internal place names
3. **Valid Arcs**: All arcs reference existing places and transitions
4. **Module References**: Substitution transitions reference existing modules
5. **Complete Socket Assignments**: All port places are assigned to sockets
6. **Colour Set Matching**: Socket and port colour sets match
7. **No Circular References**: Modules don't have circular dependencies

## Storage

Modules are automatically persisted as part of the `ColouredPetriNet` definition. The JSON codec handles serialization of all module components.

## Implementation Details

### Files Added

#### Definition Layer
- `lib/coloured_flow/definition/module.ex` - Module definition
- `lib/coloured_flow/definition/port_place.ex` - Port place definition
- `lib/coloured_flow/definition/socket_assignment.ex` - Socket assignment definition

#### Enactment Layer
- `lib/coloured_flow/enactment/module_instance.ex` - Runtime module instance tracking

#### Validation Layer
- `lib/coloured_flow/validators/definition/module_validator.ex` - Module validator
- `lib/coloured_flow/validators/exceptions/invalid_module_error.ex` - Module validation exception

#### Storage Layer
- `lib/coloured_flow/runner/storage/schemas/json_instance/codec/module.ex` - Module codec
- `lib/coloured_flow/runner/storage/schemas/json_instance/codec/port_place.ex` - Port place codec
- `lib/coloured_flow/runner/storage/schemas/json_instance/codec/socket_assignment.ex` - Socket assignment codec

#### Builder Layer
- `lib/coloured_flow/builder/module_helper.ex` - Module builder helpers

#### Tests
- `test/coloured_flow/definition/module_test.exs` - Module tests
- `test/coloured_flow/validators/definition/module_validator_test.exs` - Validator tests

### Files Modified

- `lib/coloured_flow/definition/coloured_petri_net.ex` - Added `modules` field
- `lib/coloured_flow/definition/transition.ex` - Added `subst` and `socket_assignments` fields
- `lib/coloured_flow/validators/validators.ex` - Integrated ModuleValidator
- `lib/coloured_flow/runner/storage/schemas/json_instance/codec/transition.ex` - Updated codec
- `lib/coloured_flow/runner/storage/schemas/json_instance/codec/coloured_petri_net.ex` - Updated codec

## Future Enhancements

### Module Execution
Currently, the module execution logic in the enactment layer provides the data structures but not the full execution semantics. Future work should include:

1. **Module Instantiation**: Create module instances when substitution transitions fire
2. **Token Flow**: Transfer tokens between sockets and ports
3. **Module Lifecycle**: Manage module instance state (initializing, running, completed, failed)
4. **Nested Enactments**: Support modules containing substitution transitions
5. **Module Termination**: Detect when a module instance has completed

### Additional Features
- **Fusion Places**: Allow multiple places to share the same marking
- **Module Parameters**: Support parameterized modules
- **Module Libraries**: Create reusable module libraries
- **Visual Tools**: Support for visualizing module hierarchies

## References

- [CPN Tools - Substitution Transitions](https://cpntools.org/documentation/gui/sim/subpages/subpages/)
- [Coloured Petri Nets Book](https://github.com/lmkr/cpnbook)
- Jensen, K. & Kristensen, L.M. (2009). Coloured Petri Nets: Modelling and Validation of Concurrent Systems
