# SubFlowManager Design

## Overview

`SubFlowManager` is responsible for the complete lifecycle of module execution:
1. **Resolve** module references to concrete Module definitions
2. **Start** sub-flow instances (module executions)
3. **Query** sub-flow status and state
4. **Retrieve** sub-flow results (output tokens)
5. **Manage** sub-flow lifecycle (optional: pause, resume, cancel)

## Naming Consideration

**Why not "ModuleResolver"?**
- Too narrow - only implies resolution
- Doesn't convey lifecycle management

**Why "SubFlowManager"?**
- ✅ Covers entire lifecycle
- ✅ Emphasizes that modules are executed as sub-flows
- ✅ Clear responsibility: manage sub-flow instances

**Alternatives considered:**
- `ModuleExecutor` - focuses on execution, misses query/management
- `ModuleRuntime` - too vague
- `SubstitutionHandler` - tied to CPN terminology, not intuitive

## Behaviour Callbacks

### Option A: Detailed Lifecycle (Recommended)

```elixir
defprotocol ColouredFlow.Runtime.SubFlowManager do
  @moduledoc """
  Protocol for managing sub-flow (module) lifecycle.

  A sub-flow is an instance of a module being executed as part of
  a substitution transition.
  """

  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Runtime.ModuleReference

  @typedoc "Sub-flow instance identifier"
  @type subflow_id() :: term()

  @typedoc "Sub-flow execution state"
  @type subflow_state() :: :initializing | :running | :completed | :failed | :cancelled

  @typedoc "Token marking for a place"
  @type marking() :: %{place: String.t(), tokens: term()}

  @doc """
  Resolve a module reference to a concrete Module definition.

  ## Parameters
  - `manager`: The manager instance
  - `module_ref`: Module reference to resolve
  - `options`: Runtime options (enactment_id, etc.)

  ## Returns
  - `{:ok, module}`: Successfully resolved
  - `{:error, reason}`: Resolution failed

  ## Examples

      {:ok, module} = SubFlowManager.resolve_module(
        manager,
        {:module_ref, flow_id: 123, port_specs: [...]},
        enactment_id: "parent_123"
      )
  """
  @spec resolve_module(t(), ModuleReference.t(), Keyword.t()) ::
    {:ok, Module.t()} | {:error, term()}
  def resolve_module(manager, module_ref, options)

  @doc """
  Start a sub-flow instance.

  ## Parameters
  - `manager`: The manager instance
  - `module`: The module to execute
  - `initial_marking`: Initial tokens for port places
  - `options`: Execution options

  ## Returns
  - `{:ok, subflow_id}`: Sub-flow started successfully
  - `{:error, reason}`: Failed to start

  ## Examples

      {:ok, subflow_id} = SubFlowManager.start_subflow(
        manager,
        auth_module,
        [%{place: "credentials", tokens: creds}],
        parent_enactment_id: "parent_123",
        parent_transition: "authenticate"
      )
  """
  @spec start_subflow(t(), Module.t(), [marking()], Keyword.t()) ::
    {:ok, subflow_id()} | {:error, term()}
  def start_subflow(manager, module, initial_marking, options)

  @doc """
  Query the current state of a sub-flow.

  ## Parameters
  - `manager`: The manager instance
  - `subflow_id`: The sub-flow to query
  - `options`: Query options

  ## Returns
  - `{:ok, state}`: Current state
  - `{:error, reason}`: Query failed

  ## Examples

      {:ok, :running} = SubFlowManager.query_subflow(manager, subflow_id)
  """
  @spec query_subflow(t(), subflow_id(), Keyword.t()) ::
    {:ok, subflow_state()} | {:error, term()}
  def query_subflow(manager, subflow_id, options \\ [])

  @doc """
  Get the final marking (output tokens) from a completed sub-flow.

  ## Parameters
  - `manager`: The manager instance
  - `subflow_id`: The sub-flow to get results from
  - `options`: Retrieval options

  ## Returns
  - `{:ok, marking}`: Final marking (output port tokens)
  - `{:error, reason}`: Failed to get results

  ## Examples

      {:ok, outputs} = SubFlowManager.get_subflow_result(manager, subflow_id)
      # outputs: [%{place: "success", tokens: {...}}, ...]
  """
  @spec get_subflow_result(t(), subflow_id(), Keyword.t()) ::
    {:ok, [marking()]} | {:error, term()}
  def get_subflow_result(manager, subflow_id, options \\ [])

  @doc """
  Cancel a running sub-flow (optional).

  ## Parameters
  - `manager`: The manager instance
  - `subflow_id`: The sub-flow to cancel
  - `options`: Cancellation options

  ## Returns
  - `:ok`: Successfully cancelled
  - `{:error, reason}`: Cancellation failed
  """
  @spec cancel_subflow(t(), subflow_id(), Keyword.t()) ::
    :ok | {:error, term()}
  def cancel_subflow(manager, subflow_id, options \\ [])
end
```

### Option B: Simplified (Execute-based)

```elixir
defprotocol ColouredFlow.Runtime.SubFlowManager do
  @doc """
  Resolve and execute a module reference synchronously.

  This is a simplified API that combines resolve + start + wait.

  ## Parameters
  - `manager`: The manager instance
  - `module_ref`: Module reference to execute
  - `input_tokens`: Input tokens for port places
  - `options`: Execution options

  ## Returns
  - `{:ok, output_tokens}`: Execution completed
  - `{:error, reason}`: Execution failed

  ## Examples

      {:ok, outputs} = SubFlowManager.execute(
        manager,
        {:module_ref, flow_id: 123, port_specs: [...]},
        [%{place: "input", tokens: data}],
        timeout: 5000
      )
  """
  @spec execute(t(), ModuleReference.t(), [marking()], Keyword.t()) ::
    {:ok, [marking()]} | {:error, term()}
  def execute(manager, module_ref, input_tokens, options)

  @doc """
  Start asynchronous execution (optional).

  Returns immediately with a handle for later querying.
  """
  @spec execute_async(t(), ModuleReference.t(), [marking()], Keyword.t()) ::
    {:ok, async_handle()} | {:error, term()}
  def execute_async(manager, module_ref, input_tokens, options)

  @doc """
  Wait for async execution to complete.
  """
  @spec await(t(), async_handle(), timeout()) ::
    {:ok, [marking()]} | {:error, term()}
  def await(manager, handle, timeout \\ 5000)
end
```

## Comparison

### Option A: Detailed Lifecycle

**Pros:**
- ✅ Full control over sub-flow lifecycle
- ✅ Can query intermediate state
- ✅ Can cancel long-running flows
- ✅ Matches CPN theory (module instances)

**Cons:**
- ❌ More complex API
- ❌ Need to manage subflow_id

**Use when:**
- Sub-flows are long-running
- Need to monitor progress
- Need cancellation support

### Option B: Simplified Execute

**Pros:**
- ✅ Simpler API (one call)
- ✅ No subflow_id management
- ✅ Easier to implement

**Cons:**
- ❌ Less control
- ❌ Blocking (unless async)
- ❌ Can't query intermediate state

**Use when:**
- Sub-flows are quick
- Don't need progress monitoring
- Simple use cases

## Recommendation

**Use Option A (Detailed Lifecycle)** because:

1. **Aligns with CPN theory** - Modules are instantiated as sub-enactments
2. **Future-proof** - Can add monitoring, debugging later
3. **Flexibility** - Supports both sync and async patterns
4. **Realistic** - Sub-flows may be long-running (user approval, API calls, etc.)

## Default Implementation Structure

```elixir
defmodule ColouredFlow.Runtime.SubFlowManager.Default do
  @moduledoc """
  Default sub-flow manager that:
  1. Resolves modules from database using FlowConverter
  2. Starts sub-flows as separate Enactment processes
  3. Tracks sub-flow state
  """

  defstruct [:repo, :supervisor, :cache]

  def new(opts) do
    %__MODULE__{
      repo: Keyword.fetch!(opts, :repo),
      supervisor: Keyword.get(opts, :supervisor),
      cache: Keyword.get(opts, :cache, false)
    }
  end
end

defimpl SubFlowManager, for: SubFlowManager.Default do
  def resolve_module(%{repo: repo}, module_ref, opts) do
    # Load from database using FlowConverter
    # Same as before
  end

  def start_subflow(%{supervisor: sup}, module, initial_marking, opts) do
    # Create CPN from module
    cpnet = module_to_cpnet(module)

    # Start as child enactment under supervisor
    {:ok, pid} = Enactment.start_link(
      cpnet: cpnet,
      initial_marking: initial_marking,
      parent: opts[:parent_enactment_id]
    )

    # Return identifier
    {:ok, {:enactment, pid}}
  end

  def query_subflow(_manager, {:enactment, pid}, _opts) do
    # Query enactment state
    case Enactment.get_state(pid) do
      %{status: status} -> {:ok, status}
      _ -> {:error, :not_found}
    end
  end

  def get_subflow_result(_manager, {:enactment, pid}, _opts) do
    # Get final marking from enactment
    case Enactment.get_final_marking(pid) do
      {:ok, marking} ->
        # Filter to only output port places
        {:ok, marking}
      error -> error
    end
  end

  def cancel_subflow(_manager, {:enactment, pid}, _opts) do
    # Terminate enactment
    Enactment.stop(pid)
  end
end
```

## Usage Example

```elixir
# 1. Initialize manager
manager = SubFlowManager.Default.new(
  repo: MyApp.Repo,
  supervisor: MyApp.EnactmentSupervisor
)

# 2. In substitution transition handler
def fire_substitution_transition(transition, state) do
  # Resolve module
  {:ok, module} = SubFlowManager.resolve_module(
    manager,
    transition.subst,
    enactment_id: state.id
  )

  # Prepare input tokens (from socket assignments)
  input_tokens = prepare_input_tokens(transition, state.marking)

  # Start sub-flow
  {:ok, subflow_id} = SubFlowManager.start_subflow(
    manager,
    module,
    input_tokens,
    parent_enactment_id: state.id,
    parent_transition: transition.name
  )

  # Wait for completion (or handle async)
  case wait_for_subflow(manager, subflow_id) do
    {:ok, :completed} ->
      # Get results
      {:ok, output_tokens} = SubFlowManager.get_subflow_result(
        manager,
        subflow_id
      )

      # Apply output tokens to parent marking
      apply_output_tokens(output_tokens, transition, state)

    {:ok, :failed} ->
      {:error, :subflow_failed}
  end
end

defp wait_for_subflow(manager, subflow_id) do
  # Poll or subscribe to state changes
  Stream.repeatedly(fn ->
    SubFlowManager.query_subflow(manager, subflow_id)
  end)
  |> Stream.take_while(fn
    {:ok, state} when state in [:initializing, :running] -> true
    _ -> false
  end)
  |> Stream.run()

  SubFlowManager.query_subflow(manager, subflow_id)
end
```

## Questions for Confirmation

1. **Naming**: Is `SubFlowManager` a good name? Alternatives?
2. **Callbacks**: Should we use Option A (detailed) or Option B (simplified)?
3. **Additional callbacks**: Any other operations needed?
   - Pause/resume?
   - Get intermediate state/marking?
   - List all sub-flows?
4. **Sync vs Async**: Should we support both patterns?
5. **Error handling**: What error scenarios to handle?
   - Sub-flow crashes?
   - Timeout?
   - Deadlock detection?

Let's confirm the design before implementation!
