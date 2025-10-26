# SubFlowManager Callback Invocation Timeline

## Overview

This document describes **when**, **where**, and **why** each SubFlowManager callback is invoked during the execution of a substitution transition.

## Timeline Diagram

```
Substitution Transition Fires
           │
           ▼
┌─────────────────────────────────────────────────────────┐
│ 1. resolve_module()                                     │
│    WHEN: Immediately when transition becomes enabled    │
│    WHERE: In Enactment process                          │
│    WHY: Need Module definition to understand interface  │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ 2. start_subflow()                                      │
│    WHEN: After module resolved, before transition fires │
│    WHERE: In Enactment process                          │
│    WHY: Start sub-flow execution with input tokens      │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
                   ┌────────┐
                   │ WAIT   │ ← Sub-flow executing
                   └────┬───┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ 3. query_subflow() (polling loop)                       │
│    WHEN: Periodically while waiting                     │
│    WHERE: In Enactment process                          │
│    WHY: Check if sub-flow completed                     │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
                 Sub-flow completes
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ 4. get_subflow_result()                                 │
│    WHEN: After sub-flow state is :completed             │
│    WHERE: In Enactment process                          │
│    WHY: Retrieve output tokens from sub-flow            │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
              Apply output tokens to
              parent marking & complete
                   transition

Optional:
┌─────────────────────────────────────────────────────────┐
│ 5. cancel_subflow()                                     │
│    WHEN: On timeout, error, or explicit cancellation    │
│    WHERE: In Enactment process                          │
│    WHY: Clean up sub-flow resources                     │
└─────────────────────────────────────────────────────────┘
```

## Detailed Callback Documentation

### 1. `resolve_module/3`

#### When is it called?

**Timing**: When a substitution transition becomes **enabled**

**Trigger**:
- Transition has all input tokens available
- Guard evaluates to true
- Enactment determines the transition can fire

**Frequency**: Once per transition firing (may be cached)

#### Where is it called?

**Caller**: `ColouredFlow.Runner.Enactment` process

**Context**: During binding element computation or transition firing preparation

#### Call Signature

```elixir
SubFlowManager.resolve_module(
  manager,
  module_ref,
  options
)
```

**Parameters**:
- `manager`: The SubFlowManager instance
- `module_ref`: `{:module_ref, flow_id: 123, port_specs: [...]}`
- `options`: Runtime context
  ```elixir
  [
    enactment_id: "parent_enactment_123",
    parent_transition: "authenticate_user",
    # ... additional options from enactment config
  ]
  ```

**Returns**:
```elixir
{:ok, %Module{
  name: "flow_123_module",
  port_places: [...],
  places: [...],
  transitions: [...],
  arcs: [...]
}}
```

#### Example Usage

```elixir
defmodule ColouredFlow.Runner.Enactment do
  def handle_transition_fire(transition, state) do
    if Transition.substitution?(transition) do
      # CALL POINT 1: Resolve module
      case SubFlowManager.resolve_module(
        state.subflow_manager,
        transition.subst,
        enactment_id: state.id,
        parent_transition: transition.name
      ) do
        {:ok, module} ->
          # Continue with module
          start_subflow_execution(module, transition, state)

        {:error, reason} ->
          {:error, {:module_resolution_failed, reason}}
      end
    else
      # Regular transition
      fire_regular_transition(transition, state)
    end
  end
end
```

---

### 2. `start_subflow/4`

#### When is it called?

**Timing**: Immediately after module is resolved, before transition is considered "fired"

**Trigger**:
- Module successfully resolved
- Input tokens prepared from socket assignments
- Ready to begin sub-flow execution

**Frequency**: Once per substitution transition firing

#### Where is it called?

**Caller**: `ColouredFlow.Runner.Enactment` process

**Context**: In the transition firing handler, after consuming input tokens

#### Call Signature

```elixir
SubFlowManager.start_subflow(
  manager,
  module,
  initial_marking,
  options
)
```

**Parameters**:
- `manager`: The SubFlowManager instance
- `module`: The resolved Module struct
- `initial_marking`: Initial tokens for port places
  ```elixir
  [
    %{place: "credentials_in", tokens: %{username: "alice", password: "..."}},
    # Only INPUT and IO port places
  ]
  ```
- `options`: Execution context
  ```elixir
  [
    parent_enactment_id: "parent_123",
    parent_transition: "authenticate_user",
    timeout: 30_000,  # Optional timeout
    # ... additional options
  ]
  ```

**Returns**:
```elixir
{:ok, subflow_id}
# where subflow_id might be: {:enactment, #PID<0.123.0>}
# or: "subflow_uuid_123"
```

#### Example Usage

```elixir
defmodule ColouredFlow.Runner.Enactment do
  defp start_subflow_execution(module, transition, state) do
    # Prepare input tokens from socket assignments
    input_marking = build_input_marking(
      transition.socket_assignments,
      state.marking,
      module
    )

    # CALL POINT 2: Start sub-flow
    case SubFlowManager.start_subflow(
      state.subflow_manager,
      module,
      input_marking,
      parent_enactment_id: state.id,
      parent_transition: transition.name,
      timeout: 60_000
    ) do
      {:ok, subflow_id} ->
        # Store subflow_id in state and wait for completion
        wait_for_subflow(subflow_id, transition, state)

      {:error, reason} ->
        {:error, {:subflow_start_failed, reason}}
    end
  end

  defp build_input_marking(socket_assignments, parent_marking, module) do
    input_ports = Module.input_ports(module)

    Enum.map(input_ports, fn port_place ->
      # Find corresponding socket assignment
      socket_assignment = Enum.find(
        socket_assignments,
        &(&1.port == port_place.name)
      )

      # Get tokens from parent marking at socket place
      tokens = get_tokens(parent_marking, socket_assignment.socket)

      %{place: port_place.name, tokens: tokens}
    end)
  end
end
```

---

### 3. `query_subflow/3`

#### When is it called?

**Timing**: Repeatedly while waiting for sub-flow completion

**Trigger**:
- Sub-flow has been started
- Parent enactment is waiting for completion
- Polling interval reached (e.g., every 100ms)

**Frequency**: Multiple times (polling) until sub-flow completes

#### Where is it called?

**Caller**: `ColouredFlow.Runner.Enactment` process

**Context**: In a polling loop or timeout handler

#### Call Signature

```elixir
SubFlowManager.query_subflow(
  manager,
  subflow_id,
  options
)
```

**Parameters**:
- `manager`: The SubFlowManager instance
- `subflow_id`: The identifier returned from `start_subflow`
- `options`: Query options (usually empty)

**Returns**:
```elixir
{:ok, :initializing}  # Sub-flow starting up
{:ok, :running}       # Sub-flow executing
{:ok, :completed}     # Sub-flow finished successfully
{:ok, :failed}        # Sub-flow failed
{:ok, :cancelled}     # Sub-flow was cancelled
```

#### Example Usage

```elixir
defmodule ColouredFlow.Runner.Enactment do
  defp wait_for_subflow(subflow_id, transition, state) do
    # CALL POINT 3: Query sub-flow status (polling)
    Stream.repeatedly(fn ->
      :timer.sleep(100)  # Poll interval

      case SubFlowManager.query_subflow(
        state.subflow_manager,
        subflow_id
      ) do
        {:ok, status} -> status
        {:error, _} -> :error
      end
    end)
    |> Stream.take_while(fn status ->
      status in [:initializing, :running]
    end)
    |> Stream.run()

    # Final status check
    case SubFlowManager.query_subflow(
      state.subflow_manager,
      subflow_id
    ) do
      {:ok, :completed} ->
        retrieve_subflow_results(subflow_id, transition, state)

      {:ok, :failed} ->
        {:error, :subflow_failed}

      {:error, reason} ->
        {:error, {:query_failed, reason}}
    end
  end
end
```

**Alternative: Event-based (if supported)**

```elixir
# Instead of polling, subscribe to events
defp wait_for_subflow_async(subflow_id, transition, state) do
  # Subscribe to sub-flow completion event
  :ok = SubFlowManager.subscribe(state.subflow_manager, subflow_id)

  receive do
    {:subflow_completed, ^subflow_id} ->
      retrieve_subflow_results(subflow_id, transition, state)

    {:subflow_failed, ^subflow_id, reason} ->
      {:error, {:subflow_failed, reason}}
  after
    60_000 ->
      # Timeout: cancel sub-flow
      SubFlowManager.cancel_subflow(state.subflow_manager, subflow_id)
      {:error, :timeout}
  end
end
```

---

### 4. `get_subflow_result/3`

#### When is it called?

**Timing**: After sub-flow state becomes `:completed`

**Trigger**:
- `query_subflow` returned `{:ok, :completed}`
- Ready to retrieve output tokens

**Frequency**: Once per successful sub-flow execution

#### Where is it called?

**Caller**: `ColouredFlow.Runner.Enactment` process

**Context**: After confirming sub-flow completion, before applying output tokens

#### Call Signature

```elixir
SubFlowManager.get_subflow_result(
  manager,
  subflow_id,
  options
)
```

**Parameters**:
- `manager`: The SubFlowManager instance
- `subflow_id`: The sub-flow identifier
- `options`: Retrieval options
  ```elixir
  [
    include_internal_places: false,  # Only output ports by default
    # ... other options
  ]
  ```

**Returns**:
```elixir
{:ok, [
  %{place: "success_out", tokens: %{user_id: 123}},
  %{place: "failure_out", tokens: []}
]}
```

#### Example Usage

```elixir
defmodule ColouredFlow.Runner.Enactment do
  defp retrieve_subflow_results(subflow_id, transition, state) do
    # CALL POINT 4: Get sub-flow results
    case SubFlowManager.get_subflow_result(
      state.subflow_manager,
      subflow_id
    ) do
      {:ok, output_marking} ->
        # Apply output tokens to parent marking via socket assignments
        new_marking = apply_output_tokens(
          output_marking,
          transition.socket_assignments,
          state.marking
        )

        # Update state and complete transition
        {:ok, %{state | marking: new_marking}}

      {:error, reason} ->
        {:error, {:result_retrieval_failed, reason}}
    end
  end

  defp apply_output_tokens(output_marking, socket_assignments, parent_marking) do
    Enum.reduce(output_marking, parent_marking, fn output, marking ->
      # Find socket assignment for this output port
      socket_assignment = Enum.find(
        socket_assignments,
        &(&1.port == output.place)
      )

      # Add tokens to parent marking at socket place
      add_tokens(marking, socket_assignment.socket, output.tokens)
    end)
  end
end
```

---

### 5. `cancel_subflow/3` (Optional)

#### When is it called?

**Timing**: When sub-flow needs to be terminated prematurely

**Trigger**:
- Timeout exceeded
- Parent enactment stopping/crashing
- Explicit cancellation request
- Error in parent enactment

**Frequency**: Zero or once per sub-flow (only if needed)

#### Where is it called?

**Caller**: `ColouredFlow.Runner.Enactment` process

**Context**: In timeout handler or error recovery

#### Call Signature

```elixir
SubFlowManager.cancel_subflow(
  manager,
  subflow_id,
  options
)
```

**Parameters**:
- `manager`: The SubFlowManager instance
- `subflow_id`: The sub-flow to cancel
- `options`: Cancellation options
  ```elixir
  [
    reason: :timeout,
    cleanup: true  # Clean up resources
  ]
  ```

**Returns**:
```elixir
:ok
{:error, :already_completed}  # Can't cancel completed sub-flow
```

#### Example Usage

```elixir
defmodule ColouredFlow.Runner.Enactment do
  defp wait_for_subflow_with_timeout(subflow_id, transition, state) do
    task = Task.async(fn ->
      wait_for_subflow(subflow_id, transition, state)
    end)

    case Task.yield(task, 30_000) || Task.shutdown(task) do
      {:ok, result} ->
        result

      nil ->
        # Timeout!
        # CALL POINT 5: Cancel sub-flow
        SubFlowManager.cancel_subflow(
          state.subflow_manager,
          subflow_id,
          reason: :timeout
        )
        {:error, :subflow_timeout}
    end
  end

  # Also call on enactment termination
  def terminate(reason, state) do
    # Cancel all running sub-flows
    Enum.each(state.active_subflows, fn subflow_id ->
      SubFlowManager.cancel_subflow(
        state.subflow_manager,
        subflow_id,
        reason: {:parent_terminating, reason}
      )
    end)
  end
end
```

---

## Complete Flow Example

```elixir
defmodule ColouredFlow.Runner.Enactment do
  @doc """
  Handle a substitution transition firing.

  This shows the complete flow with all callback invocations.
  """
  def handle_substitution_transition(transition, state) do
    with(
      # 1. RESOLVE MODULE
      {:ok, module} <-
        SubFlowManager.resolve_module(
          state.subflow_manager,
          transition.subst,
          enactment_id: state.id
        ),

      # 2. START SUB-FLOW
      input_marking = build_input_marking(transition, state, module),
      {:ok, subflow_id} <-
        SubFlowManager.start_subflow(
          state.subflow_manager,
          module,
          input_marking,
          parent_enactment_id: state.id,
          parent_transition: transition.name
        ),

      # 3. WAIT FOR COMPLETION (queries internally)
      {:ok, :completed} <- wait_for_completion(state.subflow_manager, subflow_id),

      # 4. GET RESULTS
      {:ok, output_marking} <-
        SubFlowManager.get_subflow_result(
          state.subflow_manager,
          subflow_id
        ),

      # Apply outputs to parent
      new_marking = apply_outputs(output_marking, transition, state.marking)
    ) do
      {:ok, %{state | marking: new_marking}}
    else
      {:error, reason} ->
        # 5. CANCEL on error (if sub-flow started)
        if subflow_id do
          SubFlowManager.cancel_subflow(
            state.subflow_manager,
            subflow_id,
            reason: reason
          )
        end

        {:error, reason}
    end
  end

  defp wait_for_completion(manager, subflow_id) do
    # Polling with query_subflow
    Stream.repeatedly(fn ->
      :timer.sleep(100)
      SubFlowManager.query_subflow(manager, subflow_id)
    end)
    |> Stream.take_while(fn
      {:ok, status} when status in [:initializing, :running] -> true
      _ -> false
    end)
    |> Stream.run()

    SubFlowManager.query_subflow(manager, subflow_id)
  end
end
```

## Summary Table

| Callback | When | Frequency | Caller | Purpose |
|----------|------|-----------|--------|---------|
| `resolve_module` | Transition enabled | Once | Enactment | Get Module definition |
| `start_subflow` | After module resolved | Once | Enactment | Start sub-flow execution |
| `query_subflow` | While waiting | Multiple (polling) | Enactment | Check completion status |
| `get_subflow_result` | After completion | Once | Enactment | Retrieve output tokens |
| `cancel_subflow` | On timeout/error | Zero or once | Enactment | Clean up resources |

## Questions?

这个调用时机清晰吗？有什么需要补充或调整的地方吗？
