# Module Resolver Design (Simplified)

## Architecture Overview

```
┌──────────────────────────────────────────┐
│  Application Initialization              │
│  - resolver = Resolver.Default.new(...)  │
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│  Enactment Initialization                │
│  - {resolver, additional_options}        │
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│  Runtime (when module needed)            │
│  - resolver.resolve(ref, options)        │
└──────────────────────────────────────────┘
```

## Design Options

### Option 1: Protocol-Based (Recommended)

```elixir
# Define protocol
defprotocol ColouredFlow.Runtime.ModuleResolver do
  @doc """
  Resolves a module reference.

  ## Parameters
  - `resolver`: The resolver instance (struct implementing this protocol)
  - `module_ref`: The module reference to resolve
  - `options`: Runtime options (merged from base + additional)

  ## Returns
  - `{:ok, module}`: Successfully resolved
  - `{:error, reason}`: Resolution failed
  """
  @spec resolve(t(), module_ref(), Keyword.t()) ::
    {:ok, Module.t()} | {:error, term()}
  def resolve(resolver, module_ref, options)
end

# Default implementation
defmodule ColouredFlow.Runtime.ModuleResolver.Default do
  @moduledoc """
  Default resolver that loads from database.
  """

  defstruct [:repo, :cache]

  @type t :: %__MODULE__{
    repo: module(),
    cache: boolean()
  }

  @doc """
  Create a new default resolver.

  ## Examples

      resolver = Default.new(repo: MyApp.Repo)
      resolver = Default.new(repo: MyApp.Repo, cache: true)
  """
  def new(opts) do
    %__MODULE__{
      repo: Keyword.fetch!(opts, :repo),
      cache: Keyword.get(opts, :cache, false)
    }
  end
end

# Protocol implementation
defimpl ColouredFlow.Runtime.ModuleResolver, for: ColouredFlow.Runtime.ModuleResolver.Default do
  alias ColouredFlow.Builder.FlowConverter
  alias ColouredFlow.Runner.Storage.Schemas

  def resolve(%{repo: repo} = _resolver, module_ref, options) do
    # options contains merged base_options ++ additional_options
    # Can include: enactment_id, parent_transition, etc.

    case module_ref do
      {:module_ref, ref_opts} ->
        load_from_ref(ref_opts, repo, options)

      _ ->
        {:error, {:invalid_module_ref, module_ref}}
    end
  end

  defp load_from_ref(ref_opts, repo, runtime_opts) do
    cond do
      Keyword.has_key?(ref_opts, :flow_id) and Keyword.has_key?(ref_opts, :port_specs) ->
        flow_id = Keyword.fetch!(ref_opts, :flow_id)
        port_specs = Keyword.fetch!(ref_opts, :port_specs)
        module_name = build_module_name("flow_#{flow_id}", runtime_opts)

        load_from_flow_id(flow_id, module_name, port_specs, repo)

      Keyword.has_key?(ref_opts, :flow_id) ->
        flow_id = Keyword.fetch!(ref_opts, :flow_id)
        module_name = build_module_name("flow_#{flow_id}", runtime_opts)

        load_from_flow_id_auto(flow_id, module_name, repo)

      true ->
        {:error, {:invalid_module_ref, "Unknown format"}}
    end
  end

  defp build_module_name(base, opts) do
    case Keyword.get(opts, :enactment_id) do
      nil -> "#{base}_module"
      id -> "#{base}_enactment_#{id}_module"
    end
  end

  defp load_from_flow_id(flow_id, module_name, port_specs, repo) do
    with {:ok, flow} <- fetch_flow(flow_id, repo) do
      module = FlowConverter.flow_to_module(
        flow.definition,
        name: module_name,
        port_specs: port_specs
      )
      {:ok, module}
    end
  end

  defp load_from_flow_id_auto(flow_id, module_name, repo) do
    with {:ok, flow} <- fetch_flow(flow_id, repo) do
      module = FlowConverter.flow_to_module_auto(flow.definition, module_name)
      {:ok, module}
    end
  end

  defp fetch_flow(flow_id, repo) do
    case repo.get(Schemas.Flow, flow_id) do
      nil -> {:error, {:flow_not_found, flow_id}}
      flow -> {:ok, flow}
    end
  end
end
```

### Option 2: Behaviour + Wrapper (Alternative)

```elixir
# Define behaviour
defmodule ColouredFlow.Runtime.ModuleResolver.Behaviour do
  @callback resolve(context :: term(), module_ref(), options :: Keyword.t()) ::
    {:ok, Module.t()} | {:error, term()}
end

# Resolver config wrapper
defmodule ColouredFlow.Runtime.ModuleResolver do
  @moduledoc """
  Wrapper for module resolver with pre-configured context.
  """

  defstruct [:impl, :context]

  @type t :: %__MODULE__{
    impl: module(),
    context: term()
  }

  @doc """
  Create a new resolver from implementation and context.
  """
  def new(impl, context) do
    %__MODULE__{impl: impl, context: context}
  end

  @doc """
  Resolve a module reference.

  This is the main entry point that Enactment will call.
  """
  def resolve(%__MODULE__{impl: impl, context: context}, module_ref, options) do
    impl.resolve(context, module_ref, options)
  end
end

# Default implementation
defmodule ColouredFlow.Runtime.ModuleResolver.Default do
  @behaviour ColouredFlow.Runtime.ModuleResolver.Behaviour

  def new(opts) do
    context = %{
      repo: Keyword.fetch!(opts, :repo),
      cache: Keyword.get(opts, :cache, false)
    }

    ColouredFlow.Runtime.ModuleResolver.new(__MODULE__, context)
  end

  @impl true
  def resolve(context, module_ref, options) do
    # Same implementation as protocol version
    # ...
  end
end
```

## Usage Comparison

### Protocol-Based (Option 1)

```elixir
# 1. Initialize
resolver = ModuleResolver.Default.new(repo: MyApp.Repo)

# 2. Pass to enactment with additional options
additional_opts = [cache_ttl: 60_000]
{:ok, enactment} = start_enactment(
  cpnet: cpnet,
  resolver: {resolver, additional_opts}
)

# 3. In Enactment
defmodule Enactment do
  def handle_substitution_transition(transition, state) do
    {resolver, additional_opts} = state.resolver

    runtime_opts = [
      enactment_id: state.id,
      parent_transition: transition.name
    ] ++ additional_opts

    # Call using protocol
    case ModuleResolver.resolve(resolver, transition.subst, runtime_opts) do
      {:ok, module} -> # ...
      {:error, reason} -> # ...
    end
  end
end
```

### Behaviour-Based (Option 2)

```elixir
# 1. Initialize
resolver = ModuleResolver.Default.new(repo: MyApp.Repo)

# 2. Pass to enactment
additional_opts = [cache_ttl: 60_000]
{:ok, enactment} = start_enactment(
  cpnet: cpnet,
  resolver: {resolver, additional_opts}
)

# 3. In Enactment (same as Option 1)
runtime_opts = [enactment_id: state.id] ++ additional_opts
ModuleResolver.resolve(resolver, ref, runtime_opts)
```

## Recommendation

**Use Option 1 (Protocol-Based)** because:

1. ✅ More idiomatic Elixir
2. ✅ Cleaner syntax: `ModuleResolver.resolve(resolver, ref, opts)`
3. ✅ Easy to implement custom resolvers
4. ✅ Protocol dispatch is efficient
5. ✅ Type safety with structs

## Complete Example (Protocol-Based)

```elixir
# Application startup
defmodule MyApp.Application do
  def start(_type, _args) do
    # Create resolver instance
    resolver = ModuleResolver.Default.new(repo: MyApp.Repo, cache: true)

    # Store in application env
    Application.put_env(:my_app, :module_resolver, resolver)

    # ...
  end
end

# Define CPN with module reference
cpnet = %ColouredPetriNet{
  transitions: [
    %Transition{
      name: "auth",
      subst: {:module_ref, flow_id: 123, port_specs: [...]},
      socket_assignments: [...]
    }
  ]
}

# Start enactment
resolver = Application.get_env(:my_app, :module_resolver)
additional_opts = [custom_key: "value"]

{:ok, enactment} = start_enactment(
  cpnet: cpnet,
  resolver: {resolver, additional_opts}
)

# Inside Enactment (when transition fires)
defmodule ColouredFlow.Runner.Enactment do
  def fire_substitution_transition(transition, state) do
    {resolver, additional_opts} = state.resolver_config

    runtime_opts = [
      enactment_id: state.id,
      parent_transition: transition.name
    ] ++ additional_opts

    # Clean syntax!
    case ModuleResolver.resolve(resolver, transition.subst, runtime_opts) do
      {:ok, module} ->
        execute_module(module, ...)

      {:error, reason} ->
        {:error, {:module_resolution_failed, reason}}
    end
  end
end
```

## Custom Resolver Example

```elixir
# Define custom resolver struct
defmodule MyApp.FileResolver do
  defstruct [:base_path]

  def new(opts) do
    %__MODULE__{
      base_path: Keyword.fetch!(opts, :base_path)
    }
  end
end

# Implement protocol
defimpl ModuleResolver, for: MyApp.FileResolver do
  def resolve(%{base_path: path}, {:module_ref, file: filename}, _opts) do
    file_path = Path.join(path, filename)

    with {:ok, content} <- File.read(file_path),
         {:ok, flow_data} <- Jason.decode(content),
         cpnet <- deserialize(flow_data) do
      module = FlowConverter.flow_to_module_auto(cpnet, filename)
      {:ok, module}
    end
  end
end

# Use it
resolver = MyApp.FileResolver.new(base_path: "/modules")
{:ok, enactment} = start_enactment(
  cpnet: cpnet,
  resolver: {resolver, []}
)
```

## Benefits

1. **Simple**: `ModuleResolver.resolve(resolver, ref, opts)`
2. **Flexible**: Easy to add custom resolvers
3. **Type-safe**: Structs ensure correct configuration
4. **Composable**: Options merge cleanly
5. **Testable**: Easy to mock resolvers
