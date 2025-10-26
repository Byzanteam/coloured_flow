# Module Resolver Design (MFA-Based)

## Architecture Overview

```
┌──────────────────────────────────────────┐
│  Application Initialization              │
│  - Create resolver context               │
│  - Form MFA: {Mod, :resolve, [context]} │
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│  Enactment Initialization                │
│  - Receives resolver_mfa                 │
│  - Stores in enactment state             │
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│  Runtime (when module needed)            │
│  - apply(Mod, :resolve, [ref, ctx, info])│
│  - Returns resolved module               │
└──────────────────────────────────────────┘
```

## Core Design

### 1. Behaviour Definition (3 parameters)

```elixir
# lib/coloured_flow/runtime/module_resolver.ex

defmodule ColouredFlow.Runtime.ModuleResolver do
  @moduledoc """
  Behaviour for module resolution.

  Implement this behaviour to provide custom module loading strategies.
  The resolver is configured externally and passed to enactment as MFA.
  """

  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Runtime.ModuleReference

  @typedoc """
  Context for module resolution.

  This is initialized once by the application and passed as part of MFA.
  Contains configuration like database repo, cache settings, etc.
  """
  @type context() :: term()

  @typedoc """
  Runtime information from enactment.

  This is provided at resolution time and contains dynamic information
  like enactment_id, current state, etc.
  """
  @type runtime_info() :: %{
    optional(:enactment_id) => term(),
    optional(:parent_transition) => binary(),
    optional(atom()) => term()
  }

  @type module_ref() :: ModuleReference.t()

  @doc """
  Resolves a module reference to a concrete Module.

  ## Parameters
  - `module_ref`: The module reference to resolve
  - `context`: Resolver context (initialized externally)
  - `runtime_info`: Runtime information from enactment

  ## Returns
  - `{:ok, module}`: Successfully resolved module
  - `{:error, reason}`: Failed to resolve

  ## Examples

      # Called by enactment via MFA
      @impl true
      def resolve(module_ref, context, runtime_info) do
        # Use context for configuration (repo, cache, etc.)
        # Use runtime_info for dynamic decisions
        {:ok, module}
      end
  """
  @callback resolve(module_ref(), context(), runtime_info()) ::
    {:ok, Module.t()} | {:error, term()}
end
```

### 2. MFA Type Definition

```elixir
# lib/coloured_flow/runtime/module_resolver.ex

defmodule ColouredFlow.Runtime.ModuleResolver do
  # ... behaviour definition ...

  @typedoc """
  Module resolver in MFA form.

  The tuple contains:
  - module: Module implementing ModuleResolver behaviour
  - function: Always :resolve
  - args: List containing [context] (pre-initialized)

  When calling: apply(module, :resolve, [module_ref, context, runtime_info])
  """
  @type mfa() :: {module(), :resolve, [context()]}

  @doc """
  Helper to create MFA from resolver module and context.

  ## Examples

      context = MyResolver.init(repo: MyApp.Repo)
      mfa = ModuleResolver.to_mfa(MyResolver, context)
      # Returns: {MyResolver, :resolve, [context]}
  """
  @spec to_mfa(module(), context()) :: mfa()
  def to_mfa(resolver_module, context) when is_atom(resolver_module) do
    {resolver_module, :resolve, [context]}
  end

  @doc """
  Helper to call MFA with module reference and runtime info.

  ## Examples

      mfa = {MyResolver, :resolve, [context]}
      runtime_info = %{enactment_id: 123}
      {:ok, module} = ModuleResolver.call_mfa(mfa, module_ref, runtime_info)
  """
  @spec call_mfa(mfa(), module_ref(), runtime_info()) ::
    {:ok, Module.t()} | {:error, term()}
  def call_mfa({module, :resolve, [context]}, module_ref, runtime_info) do
    apply(module, :resolve, [module_ref, context, runtime_info])
  end
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
  alias ColouredFlow.Runner.Storage.Schemas

  @typedoc """
  Context for default resolver.
  """
  @type context() :: %{
    repo: module(),
    cache: boolean(),
    cache_store: map()
  }

  @doc """
  Initialize resolver context.

  ## Options
  - `:repo` (required) - Ecto repo for loading flows
  - `:cache` (optional) - Enable caching (default: false)

  ## Examples

      context = Default.init(repo: MyApp.Repo)
      mfa = ModuleResolver.to_mfa(Default, context)
  """
  @spec init(Keyword.t()) :: context()
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)

    %{
      repo: repo,
      cache: Keyword.get(opts, :cache, false),
      cache_store: %{}
    }
  end

  @impl ColouredFlow.Runtime.ModuleResolver
  def resolve(module_ref, context, runtime_info)

  # Resolve by flow_id with port_specs
  def resolve({:module_ref, opts}, context, runtime_info) when is_list(opts) do
    cond do
      Keyword.has_key?(opts, :flow_id) and Keyword.has_key?(opts, :port_specs) ->
        flow_id = Keyword.fetch!(opts, :flow_id)
        port_specs = Keyword.fetch!(opts, :port_specs)

        # Can use runtime_info to customize module name
        module_name = build_module_name("flow_#{flow_id}", runtime_info)

        load_from_flow_id(flow_id, module_name, port_specs, context)

      Keyword.has_key?(opts, :flow_id) and Keyword.has_key?(opts, :module_name) ->
        flow_id = Keyword.fetch!(opts, :flow_id)
        module_name = Keyword.fetch!(opts, :module_name)

        load_from_flow_id_auto(flow_id, module_name, context)

      Keyword.has_key?(opts, :flow_name) and Keyword.has_key?(opts, :port_specs) ->
        flow_name = Keyword.fetch!(opts, :flow_name)
        port_specs = Keyword.fetch!(opts, :port_specs)
        module_name = build_module_name(flow_name, runtime_info)

        load_from_flow_name(flow_name, module_name, port_specs, context)

      Keyword.has_key?(opts, :flow_name) and Keyword.has_key?(opts, :module_name) ->
        flow_name = Keyword.fetch!(opts, :flow_name)
        module_name = Keyword.fetch!(opts, :module_name)

        load_from_flow_name_auto(flow_name, module_name, context)

      true ->
        {:error, {:invalid_module_ref, "Unknown module reference format"}}
    end
  end

  defp build_module_name(base_name, runtime_info) do
    # Can incorporate enactment_id to create unique module names
    case Map.get(runtime_info, :enactment_id) do
      nil -> "#{base_name}_module"
      enactment_id -> "#{base_name}_enactment_#{enactment_id}_module"
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

### 4. Usage in Enactment

```elixir
# When starting an enactment

# 1. Application level: Initialize resolver
resolver_context = ModuleResolver.Default.init(repo: MyApp.Repo)
resolver_mfa = ModuleResolver.to_mfa(ModuleResolver.Default, resolver_context)

# 2. Pass to enactment
{:ok, enactment_pid} = Enactment.start_link(
  cpnet: cpnet,
  resolver: resolver_mfa,
  # ... other options
)

# 3. Inside Enactment GenServer
defmodule ColouredFlow.Runner.Enactment do
  def init(opts) do
    state = %{
      cpnet: opts[:cpnet],
      resolver_mfa: opts[:resolver],
      enactment_id: generate_id(),
      # ...
    }
    {:ok, state}
  end

  # When a substitution transition fires
  defp fire_substitution_transition(transition, state) do
    if is_module_ref?(transition.subst) do
      runtime_info = %{
        enactment_id: state.enactment_id,
        parent_transition: transition.name
      }

      case ModuleResolver.call_mfa(state.resolver_mfa, transition.subst, runtime_info) do
        {:ok, module} ->
          # Use the resolved module
          execute_module(module, ...)

        {:error, reason} ->
          {:error, {:module_resolution_failed, reason}}
      end
    else
      # Static module reference
      module = find_module_in_cpnet(state.cpnet, transition.subst)
      execute_module(module, ...)
    end
  end
end
```

## Complete Example

```elixir
# 1. Application startup
defmodule MyApp.Application do
  def start(_type, _args) do
    # Initialize resolver
    resolver_context = ModuleResolver.Default.init(repo: MyApp.Repo)
    resolver_mfa = ModuleResolver.to_mfa(ModuleResolver.Default, resolver_context)

    # Store in application env or pass to supervisor
    Application.put_env(:my_app, :module_resolver, resolver_mfa)

    # Start supervisors...
  end
end

# 2. Create CPN with module reference
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

# 3. Start enactment with resolver
resolver_mfa = Application.get_env(:my_app, :module_resolver)

{:ok, enactment_pid} = Enactment.start_link(
  cpnet: cpnet,
  resolver: resolver_mfa,
  initial_marking: [...]
)

# 4. When transition fires, enactment calls:
# apply(ModuleResolver.Default, :resolve, [
#   {:module_ref, flow_id: 123, port_specs: [...]},
#   resolver_context,
#   %{enactment_id: "abc123", parent_transition: "authenticate"}
# ])
```

## Benefits

1. **Lazy Resolution**: Modules resolved only when needed (at transition fire time)
2. **Runtime Context**: Resolver can use enactment info for decisions
3. **No Global State**: Resolver configured per enactment
4. **Testable**: Easy to mock MFA in tests
5. **Flexible**: Can use different resolvers for different enactments

## Key Changes from Previous Design

1. **Behaviour signature**: `resolve/3` instead of `resolve/2`
2. **Third parameter**: `runtime_info` with enactment context
3. **MFA format**: `{Module, :resolve, [context]}` for easy passing
4. **Helper functions**: `to_mfa/2` and `call_mfa/3` for convenience
5. **Lazy loading**: Resolution happens at runtime, not upfront
