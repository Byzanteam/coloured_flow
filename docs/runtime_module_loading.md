# Runtime Module Loading

This document describes the runtime module loading and management system in ColouredFlow.

## Architecture Overview

The runtime module loading system consists of four main components:

```
┌─────────────────────────────────────────────────────────┐
│                   ColouredPetriNet                       │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Substitution Transition                         │   │
│  │  - subst: {:module_ref, ...}                    │   │
│  └──────────────────┬──────────────────────────────┘   │
└─────────────────────┼──────────────────────────────────┘
                      │
                      ▼
         ┌────────────────────────┐
         │   ModuleResolver       │
         │  (Resolve references)  │
         └────────────┬───────────┘
                      │
                      ▼
         ┌────────────────────────┐
         │   ModuleLoader         │
         │  (Load from sources)   │
         └────────────┬───────────┘
                      │
         ┌────────────┴───────────┐
         │                        │
         ▼                        ▼
┌────────────────┐      ┌────────────────┐
│ ModuleRegistry │      │ ModuleSource   │
│  (In-memory)   │      │ (DB/File/API)  │
└────────────────┘      └────────────────┘
```

## Key Concepts

### 1. Module Reference

A module reference allows substitution transitions to reference modules dynamically:

```elixir
# Reference by name (from registry)
%Transition{
  name: "auth",
  subst: {:module_ref, name: "authentication"}
}

# Reference by Flow ID (load from database)
%Transition{
  name: "auth",
  subst: {:module_ref, flow_id: 123, port_specs: [...]}
}

# Reference by Flow name (load from database)
%Transition{
  name: "auth",
  subst: {:module_ref, flow_name: "auth_flow_v2", port_specs: [...]}
}

# Direct module name (static, as before)
%Transition{
  name: "auth",
  subst: "authentication"  # Must be in cpnet.modules
}
```

### 2. Module Registry

An in-memory registry that stores loaded modules:

```elixir
# Start the registry
{:ok, _pid} = ColouredFlow.Runtime.ModuleRegistry.start_link()

# Register a module
ModuleRegistry.register("authentication", auth_module)

# Get a module
{:ok, module} = ModuleRegistry.get("authentication")

# List all modules
modules = ModuleRegistry.list()

# Unregister
:ok = ModuleRegistry.unregister("authentication")
```

### 3. Module Loader

Loads modules from various sources:

```elixir
# Load from database by Flow ID
{:ok, module} = ModuleLoader.load_from_flow(
  flow_id: 123,
  port_specs: [{"input", :input}, {"output", :output}]
)

# Load from database by Flow name
{:ok, module} = ModuleLoader.load_from_flow(
  flow_name: "authentication_v2",
  port_specs: [...]
)

# Auto-detect and load
{:ok, module} = ModuleLoader.load_from_flow_auto(
  flow_id: 123,
  module_name: "authentication"
)
```

### 4. Module Resolver

Resolves module references at runtime:

```elixir
# Resolve a module reference
{:ok, module} = ModuleResolver.resolve(
  {:module_ref, flow_id: 123, port_specs: [...]},
  context
)

# Resolve all module references in a CPN
{:ok, cpnet_with_modules} = ModuleResolver.resolve_all(cpnet)
```

## Usage Scenarios

### Scenario 1: Load Flow as Module on Demand

```elixir
# Define a transition that references a Flow by ID
cpnet = %ColouredPetriNet{
  places: [...],
  transitions: [
    %Transition{
      name: "authenticate",
      subst: {:module_ref,
        flow_id: 123,
        port_specs: [
          {"credentials", :input},
          {"success", :output},
          {"failure", :output}
        ]
      },
      socket_assignments: [...]
    }
  ]
}

# At runtime, before execution
{:ok, resolved_cpnet} = ModuleResolver.resolve_all(cpnet)

# Now resolved_cpnet has the module loaded
# resolved_cpnet.modules contains the authentication module
```

### Scenario 2: Module Registry for Shared Modules

```elixir
# Application startup: Pre-register common modules
defmodule MyApp.Application do
  def start(_type, _args) do
    # Load and register authentication module
    {:ok, auth_module} = ModuleLoader.load_from_flow(
      flow_id: 123,
      port_specs: [...]
    )
    ModuleRegistry.register("authentication", auth_module)

    # Load and register other modules
    ModuleRegistry.register("notification", notif_module)
    ModuleRegistry.register("email", email_module)

    # ... start supervisors
  end
end

# In your flows: Reference by name
cpnet = %ColouredPetriNet{
  transitions: [
    %Transition{
      name: "auth",
      subst: {:module_ref, name: "authentication"},
      socket_assignments: [...]
    }
  ]
}
```

### Scenario 3: Versioned Modules

```elixir
# Register multiple versions
ModuleRegistry.register("authentication:v1", auth_module_v1)
ModuleRegistry.register("authentication:v2", auth_module_v2)
ModuleRegistry.register("authentication", auth_module_v2)  # Latest

# Reference specific version
%Transition{
  subst: {:module_ref, name: "authentication:v1"}
}

# Or use latest
%Transition{
  subst: {:module_ref, name: "authentication"}
}
```

### Scenario 4: Hot Reload

```elixir
# Update a module at runtime
new_auth_module = build_new_auth_module()
ModuleRegistry.update("authentication", new_auth_module)

# New enactments will use the updated module
# Existing enactments continue with their original module
```

## Implementation Details

### Module Reference Types

```elixir
@type module_ref() ::
  # Reference by name in registry
  {:module_ref, name: String.t()} |

  # Reference by Flow ID with port specs
  {:module_ref, flow_id: integer(), port_specs: [port_spec()]} |

  # Reference by Flow ID with auto-detection
  {:module_ref, flow_id: integer(), module_name: String.t()} |

  # Reference by Flow name
  {:module_ref, flow_name: String.t(), port_specs: [port_spec()]} |

  # Reference by Flow name with auto-detection
  {:module_ref, flow_name: String.t(), module_name: String.t()}
```

### Caching Strategy

1. **Registry Cache**: Modules in registry are kept in memory
2. **Loader Cache**: Recently loaded modules are cached (with TTL)
3. **Enactment Cache**: Each enactment keeps its resolved modules

### Error Handling

```elixir
# Module not found
{:error, :module_not_found}

# Flow not found
{:error, :flow_not_found}

# Invalid port specs
{:error, {:invalid_port_specs, reason}}

# Load failure
{:error, {:load_failed, reason}}
```

## Configuration

```elixir
# In config/config.exs
config :coloured_flow, ColouredFlow.Runtime.ModuleRegistry,
  # Enable/disable registry
  enabled: true,

  # Cache TTL for loaded modules (milliseconds)
  cache_ttl: 60_000,

  # Max cached modules
  max_cache_size: 100

config :coloured_flow, ColouredFlow.Runtime.ModuleLoader,
  # Default repo for loading flows
  repo: MyApp.Repo,

  # Auto-register loaded modules
  auto_register: true
```

## Migration Guide

### Before (Static Modules)

```elixir
# Define module in the same CPN
cpnet = %ColouredPetriNet{
  modules: [auth_module, email_module],
  transitions: [
    %Transition{
      name: "auth",
      subst: "authentication"  # Static reference
    }
  ]
}
```

### After (Dynamic Loading)

```elixir
# Just reference, no need to embed
cpnet = %ColouredPetriNet{
  modules: [],  # Empty!
  transitions: [
    %Transition{
      name: "auth",
      subst: {:module_ref, flow_id: 123, port_specs: [...]}
    }
  ]
}

# Resolve at runtime
{:ok, resolved_cpnet} = ModuleResolver.resolve_all(cpnet)
# Now resolved_cpnet.modules contains the loaded module
```

## Benefits

1. **Separation of Concerns**: Flows and modules can be managed independently
2. **Reusability**: One Flow can be used as a module in many other flows
3. **Versioning**: Easy to manage multiple versions of modules
4. **Hot Updates**: Update modules without restarting
5. **Lazy Loading**: Load modules only when needed
6. **Memory Efficiency**: Share module definitions across enactments

## Future Enhancements

1. **Remote Module Loading**: Load modules from remote services
2. **Module Marketplace**: Share modules across organizations
3. **Dependency Management**: Resolve transitive module dependencies
4. **Module Signing**: Verify module integrity
5. **Performance Monitoring**: Track module load times and cache hits
