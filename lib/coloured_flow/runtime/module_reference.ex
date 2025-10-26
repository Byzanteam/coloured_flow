defmodule ColouredFlow.Runtime.ModuleReference do
  @moduledoc """
  Type definition for module references.

  A module reference allows dynamic loading of modules at runtime.
  It can reference a module by flow ID, flow name, or custom identifier.

  ## Usage

  Module references are used in substitution transitions to load modules
  dynamically instead of embedding them statically in the CPN definition.

  ## Examples

      # Reference by flow ID with explicit port specifications
      {:module_ref,
        flow_id: 123,
        port_specs: [
          {"credentials", :input},
          {"success", :output},
          {"failure", :output}
        ]
      }

      # Reference by flow ID with automatic port detection
      {:module_ref,
        flow_id: 123,
        module_name: "authentication"
      }

      # Reference by flow name
      {:module_ref,
        flow_name: "auth_flow_v2",
        port_specs: [...]
      }

      # Custom reference (for user-defined resolvers)
      {:module_ref,
        custom: %{api_id: "auth-123", version: "v2"}
      }
  """

  @typedoc """
  Port specification for a module interface.

  Defines the name and direction of a port place:
  - `:input` - Input port (receives tokens from parent)
  - `:output` - Output port (sends tokens to parent)
  - `:io` - Input/output port (bidirectional)
  """
  @type port_spec() :: {String.t(), :input | :output | :io}

  @typedoc """
  Module reference type.

  A module reference can specify:

  1. **Flow ID with port specs**: Load from database by ID, specify ports
  2. **Flow ID with module name**: Load from database, auto-detect ports
  3. **Flow name with port specs**: Load from database by name, specify ports
  4. **Flow name with module name**: Load from database by name, auto-detect ports
  5. **Custom**: User-defined reference format for custom resolvers

  ## Examples

      # Explicit port specification
      {:module_ref, flow_id: 123, port_specs: [{"in", :input}, {"out", :output}]}

      # Auto-detect ports
      {:module_ref, flow_id: 123, module_name: "my_module"}

      # By flow name
      {:module_ref, flow_name: "authentication", port_specs: [...]}

      # Custom format
      {:module_ref, custom: %{source: :api, id: "mod-123"}}
  """
  @type t() ::
          {:module_ref, flow_id: pos_integer(), port_specs: [port_spec()]}
          | {:module_ref, flow_id: pos_integer(), module_name: String.t()}
          | {:module_ref, flow_name: String.t(), port_specs: [port_spec()]}
          | {:module_ref, flow_name: String.t(), module_name: String.t()}
          | {:module_ref, custom: term()}
end
