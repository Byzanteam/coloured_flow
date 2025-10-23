# Module Resolver Design (Behaviour-Based)

## Architecture Overview

```
┌─────────────────────────────────────────┐
│  ColouredPetriNet with module_ref       │
│  - transitions with {:module_ref, ...}   │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  resolve_modules(cpnet, resolver)        │
│  - Finds all module_ref                  │
│  - Calls resolver.resolve() for each     │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  ModuleResolver (Behaviour)              │
│  @callback resolve(ref, ctx) -> module   │
└──────────────┬──────────────────────────┘
               │
         ┌─────┴─────┐
         ▼           ▼
┌──────────────┐  ┌──────────────────┐
│ Default      │  │ User Custom      │
│ (from DB)    │  │ (from anywhere)  │
└──────────────┘  └──────────────────┘
```

## Core Components

### 1. ModuleReference (Type Definition)

```elixir
# lib/coloured_flow/runtime/module_reference.ex

defmodule ColouredFlow.Runtime.ModuleReference do
  @moduledoc """
  Type definition for module references.

  A module reference allows dynamic loading of modules at runtime.
  """

  alias ColouredFlow.Builder.FlowConverter

  @type port_spec() :: {String.t(), :input | :output | :io}

  @type t() ::
    {:module_ref, flow_id: pos_integer(), port_specs: [port_spec()]}
    | {:module_ref, flow_id: pos_integer(), module_name: String.t()}
    | {:module_ref, flow_name: String.t(), port_specs: [port_spec()]}
    | {:module_ref, flow_name: String.t(), module_name: String.t()}
    | {:module_ref, custom: term()}  # For user-defined references
end
```

### 2. ModuleResolver (Behaviour)

```elixir
# lib/coloured_flow/runtime/module_resolver.ex

defmodule ColouredFlow.Runtime.ModuleResolver do
  @moduledoc """
  Behaviour for module resolution.

  Implement this behaviour to provide custom module loading strategies.
  """

  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Runtime.ModuleReference

  @type context() :: map()
  @type module_ref() :: ModuleReference.t()

  @doc """
  Resolves a module reference to a concrete Module.

  ## Parameters
  - `module_ref`: The module reference to resolve
  - `context`: Additional context (e.g., repo, cache, options)

  ## Returns
  - `{:ok, module}`: Successfully resolved module
  - `{:error, reason}`: Failed to resolve
  """
  @callback resolve(module_ref(), context()) ::
    {:ok, Module.t()} | {:error, term()}
end
```

### 3. Default Resolver Implementation

```elixir
# lib/coloured_flow/runtime/module_resolver/default.ex

defmodule ColouredFlow.Runtime.ModuleResolver.Default do
  @moduledoc """
  Default module resolver implementation.

  Loads modules from the database using FlowConverter.
  """

  @behaviour ColouredFlow.Runtime.ModuleResolver

  alias ColouredFlow.Builder.FlowConverter
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Runner.Storage.Schemas

  @doc """
  Creates a new default resolver with options.

  ## Options
  - `:repo` (required) - Ecto repo for loading flows
  - `:cache` (optional) - Enable caching (default: false)
  - `:cache_ttl` (optional) - Cache TTL in milliseconds

  ## Examples

      resolver = Default.new(repo: MyApp.Repo)
      resolver = Default.new(repo: MyApp.Repo, cache: true)
  """
  @spec new(Keyword.t()) :: context()
  def new(opts) do
    repo = Keyword.fetch!(opts, :repo)

    %{
      repo: repo,
      cache: Keyword.get(opts, :cache, false),
      cache_ttl: Keyword.get(opts, :cache_ttl, 60_000),
      cache_store: %{}  # Simple in-memory cache
    }
  end

  @impl true
  def resolve(module_ref, context)

  # Resolve by flow_id with port_specs
  def resolve({:module_ref, opts}, context) when is_list(opts) do
    cond do
      Keyword.has_key?(opts, :flow_id) and Keyword.has_key?(opts, :port_specs) ->
        flow_id = Keyword.fetch!(opts, :flow_id)
        port_specs = Keyword.fetch!(opts, :port_specs)
        module_name = "flow_#{flow_id}_module"

        load_from_flow_id(flow_id, module_name, port_specs, context)

      Keyword.has_key?(opts, :flow_id) and Keyword.has_key?(opts, :module_name) ->
        flow_id = Keyword.fetch!(opts, :flow_id)
        module_name = Keyword.fetch!(opts, :module_name)

        load_from_flow_id_auto(flow_id, module_name, context)

      Keyword.has_key?(opts, :flow_name) and Keyword.has_key?(opts, :port_specs) ->
        flow_name = Keyword.fetch!(opts, :flow_name)
        port_specs = Keyword.fetch!(opts, :port_specs)
        module_name = "#{flow_name}_module"

        load_from_flow_name(flow_name, module_name, port_specs, context)

      Keyword.has_key?(opts, :flow_name) and Keyword.has_key?(opts, :module_name) ->
        flow_name = Keyword.fetch!(opts, :flow_name)
        module_name = Keyword.fetch!(opts, :module_name)

        load_from_flow_name_auto(flow_name, module_name, context)

      true ->
        {:error, {:invalid_module_ref, "Unknown module reference format"}}
    end
  end

  defp load_from_flow_id(flow_id, module_name, port_specs, context) do
    with {:ok, flow} <- fetch_flow_by_id(flow_id, context),
         {:ok, module} <- convert_flow_to_module(flow, module_name, port_specs) do
      {:ok, module}
    end
  end

  defp load_from_flow_id_auto(flow_id, module_name, context) do
    with {:ok, flow} <- fetch_flow_by_id(flow_id, context) do
      module = FlowConverter.flow_to_module_auto(flow.definition, module_name)
      {:ok, module}
    end
  end

  defp load_from_flow_name(flow_name, module_name, port_specs, context) do
    with {:ok, flow} <- fetch_flow_by_name(flow_name, context),
         {:ok, module} <- convert_flow_to_module(flow, module_name, port_specs) do
      {:ok, module}
    end
  end

  defp load_from_flow_name_auto(flow_name, module_name, context) do
    with {:ok, flow} <- fetch_flow_by_name(flow_name, context) do
      module = FlowConverter.flow_to_module_auto(flow.definition, module_name)
      {:ok, module}
    end
  end

  defp fetch_flow_by_id(flow_id, %{repo: repo}) do
    case repo.get(Schemas.Flow, flow_id) do
      nil -> {:error, {:flow_not_found, flow_id}}
      flow -> {:ok, flow}
    end
  end

  defp fetch_flow_by_name(flow_name, %{repo: repo}) do
    import Ecto.Query

    query = from f in Schemas.Flow, where: f.name == ^flow_name

    case repo.one(query) do
      nil -> {:error, {:flow_not_found, flow_name}}
      flow -> {:ok, flow}
    end
  end

  defp convert_flow_to_module(flow, module_name, port_specs) do
    module = FlowConverter.flow_to_module(
      flow.definition,
      name: module_name,
      port_specs: port_specs
    )

    {:ok, module}
  rescue
    error -> {:error, {:conversion_failed, error}}
  end
end
```

### 4. Resolution Function

```elixir
# Add to lib/coloured_flow/definition/coloured_petri_net.ex

defmodule ColouredFlow.Definition.ColouredPetriNet do
  # ... existing code ...

  alias ColouredFlow.Runtime.ModuleResolver

  @doc """
  Resolves all module references in the CPN using the provided resolver.

  ## Parameters
  - `cpnet`: The ColouredPetriNet to resolve
  - `resolver_impl`: Module implementing ModuleResolver behaviour
  - `context`: Context passed to resolver.resolve/2

  ## Returns
  - `{:ok, resolved_cpnet}`: CPN with all references resolved
  - `{:error, reason}`: Resolution failed

  ## Examples

      # Using default resolver
      resolver = ModuleResolver.Default.new(repo: MyApp.Repo)
      {:ok, resolved} = ColouredPetriNet.resolve_modules(cpnet,
        ModuleResolver.Default,
        resolver
      )

      # Using custom resolver
      {:ok, resolved} = ColouredPetriNet.resolve_modules(cpnet,
        MyApp.CustomResolver,
        custom_context
      )
  """
  @spec resolve_modules(t(), module(), ModuleResolver.context()) ::
    {:ok, t()} | {:error, term()}
  def resolve_modules(%__MODULE__{} = cpnet, resolver_impl, context) do
    # Find all substitution transitions with module_ref
    refs_to_resolve =
      cpnet.transitions
      |> Enum.filter(&is_module_ref?(&1.subst))
      |> Enum.map(fn transition -> {transition, transition.subst} end)

    # Resolve each reference
    case resolve_all_refs(refs_to_resolve, resolver_impl, context, %{}) do
      {:ok, resolved_modules} ->
        # Update CPN with resolved modules and static references
        updated_cpnet = apply_resolved_modules(cpnet, resolved_modules)
        {:ok, updated_cpnet}

      {:error, _reason} = error ->
        error
    end
  end

  defp is_module_ref?({:module_ref, _opts}), do: true
  defp is_module_ref?(_), do: false

  defp resolve_all_refs([], _resolver_impl, _context, resolved) do
    {:ok, resolved}
  end

  defp resolve_all_refs([{transition, ref} | rest], resolver_impl, context, resolved) do
    # Check if already resolved (dedup)
    ref_key = ref_to_key(ref)

    if Map.has_key?(resolved, ref_key) do
      resolve_all_refs(rest, resolver_impl, context, resolved)
    else
      case resolver_impl.resolve(ref, context) do
        {:ok, module} ->
          updated_resolved = Map.put(resolved, ref_key, module)
          resolve_all_refs(rest, resolver_impl, context, updated_resolved)

        {:error, reason} ->
          {:error, {:module_resolution_failed, transition.name, reason}}
      end
    end
  end

  defp ref_to_key({:module_ref, opts}), do: {:module_ref, Enum.sort(opts)}

  defp apply_resolved_modules(cpnet, resolved_modules) do
    # Add resolved modules to cpnet.modules
    new_modules = Map.values(resolved_modules)

    # Update transitions to use static module names
    updated_transitions =
      Enum.map(cpnet.transitions, fn transition ->
        if is_module_ref?(transition.subst) do
          ref_key = ref_to_key(transition.subst)
          module = Map.fetch!(resolved_modules, ref_key)
          %{transition | subst: module.name}
        else
          transition
        end
      end)

    %{cpnet |
      modules: cpnet.modules ++ new_modules,
      transitions: updated_transitions
    }
  end
end
```

## Usage Examples

### Example 1: Using Default Resolver

```elixir
# 1. Define CPN with module references
cpnet = %ColouredPetriNet{
  colour_sets: [...],
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
  ],
  arcs: [...]
}

# 2. Create resolver
resolver = ColouredFlow.Runtime.ModuleResolver.Default.new(repo: MyApp.Repo)

# 3. Resolve modules
{:ok, resolved_cpnet} = ColouredPetriNet.resolve_modules(
  cpnet,
  ColouredFlow.Runtime.ModuleResolver.Default,
  resolver
)

# 4. Now resolved_cpnet has the module loaded
# resolved_cpnet.modules contains the authentication module
# The transition now uses static reference: subst: "flow_123_module"
```

### Example 2: Custom Resolver (Load from File)

```elixir
defmodule MyApp.FileModuleResolver do
  @behaviour ColouredFlow.Runtime.ModuleResolver

  @impl true
  def resolve({:module_ref, file_path: path, module_name: name}, _context) do
    with {:ok, content} <- File.read(path),
         {:ok, flow} <- Jason.decode(content),
         cpnet <- deserialize_flow(flow) do

      module = FlowConverter.flow_to_module_auto(cpnet, name)
      {:ok, module}
    end
  end
end

# Usage
cpnet = %ColouredPetriNet{
  transitions: [
    %Transition{
      subst: {:module_ref,
        file_path: "/path/to/auth.json",
        module_name: "authentication"
      }
    }
  ]
}

{:ok, resolved} = ColouredPetriNet.resolve_modules(
  cpnet,
  MyApp.FileModuleResolver,
  %{}
)
```

### Example 3: Custom Resolver (Load from API)

```elixir
defmodule MyApp.APIModuleResolver do
  @behaviour ColouredFlow.Runtime.ModuleResolver

  @impl true
  def resolve({:module_ref, api_id: id, port_specs: specs}, context) do
    api_url = context.api_url

    with {:ok, response} <- HTTPoison.get("#{api_url}/modules/#{id}"),
         {:ok, flow_data} <- Jason.decode(response.body),
         cpnet <- deserialize_flow(flow_data) do

      module = FlowConverter.flow_to_module(cpnet,
        name: "api_module_#{id}",
        port_specs: specs
      )
      {:ok, module}
    end
  end
end
```

## Benefits

1. **No Global State**: No registry, no global GenServer
2. **Flexible**: Users can implement any loading strategy
3. **Testable**: Easy to mock resolver in tests
4. **Composable**: Can chain or combine resolvers
5. **Explicit**: Resolver is passed explicitly, clear dependencies

## Questions?

这个方案清晰吗？有什么需要调整的地方吗？
