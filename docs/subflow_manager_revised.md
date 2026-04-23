# SubFlowManager Design (Revised)

## Naming Decision

**Recommendation: Use "Child Enactment"**

### Comparison

| Term | Pros | Cons | Score |
|------|------|------|-------|
| **sub enactment** | Clear hierarchy | "sub" prefix less common | 7/10 |
| **child enactment** | ✅ Standard parent-child terminology<br>✅ Matches OTP supervisor pattern<br>✅ Clear relationship | None | **9/10** ✅ |
| **subflow** | Short | Not aligned with CPN terminology | 5/10 |

**Decision**: Use **"child enactment"** because:
- Aligns with OTP conventions (supervisor-child)
- Makes parent-child relationship explicit
- Consistent with ColouredFlow terminology (enactment is core concept)
- More accurate: modules execute as enactment instances

---

## Core Design Principles

### 1. Message-Based Communication (No Polling)

Child enactments send messages to parent when state changes:

```elixir
# Child enactment sends messages to parent
send(parent_pid, {:child_enactment_completed, child_id, output_marking})
send(parent_pid, {:child_enactment_failed, child_id, reason})
```

**Benefits**:
- ✅ More efficient (no polling overhead)
- ✅ Reactive (immediate notification)
- ✅ Idiomatic Elixir/OTP
- ✅ Supports both sync and async patterns

### 2. No Direct Cancellation (Token-Based Control)

Child enactments cannot be forcefully cancelled. Termination is controlled through Petri Net semantics:

**Wrong approach** (imperative):
```elixir
# ❌ Direct cancellation breaks CPN semantics
SubFlowManager.cancel_child_enactment(child_id)
```

**Correct approach** (declarative):
```elixir
# ✅ Send cancellation token to child enactment
# Child enactment decides how to handle based on its CPN definition
SubFlowManager.send_cancellation_token(child_id, cancel_token)
```

**Why?**
- Maintains Petri Net semantics
- Child enactment controls its own lifecycle
- Cancellation is part of the workflow logic, not external control
- More predictable and testable

### 3. Token Sharing Through Port/Socket Mapping

Parent and child enactments share tokens through **socket assignments**:

```
Parent Enactment                    Child Enactment (Module)
┌──────────────────┐               ┌──────────────────┐
│ Socket Place     │               │ Port Place       │
│ "user_input"     │──────────────>│ "credentials_in" │ (INPUT)
│ tokens: {...}    │   Copy        │ tokens: {...}    │
└──────────────────┘   tokens      └──────────────────┘
                                              │
                                              │ Execute
                                              ▼
┌──────────────────┐               ┌──────────────────┐
│ Socket Place     │<──────────────│ Port Place       │ (OUTPUT)
│ "auth_result"    │   Copy        │ "success_out"    │
│ tokens: {...}    │   tokens      │ tokens: {...}    │
└──────────────────┘               └──────────────────┘
```

**Token Flow**:
1. **Before child starts**: Copy input tokens from parent sockets → child input ports
2. **Child executes**: Tokens flow through child enactment's CPN
3. **After child completes**: Copy output tokens from child output ports → parent sockets

---

## Revised Behaviour Definition

```elixir
defprotocol ColouredFlow.Runtime.SubFlowManager do
  @moduledoc """
  Protocol for managing child enactment (module execution) lifecycle.

  A child enactment is an instance of a module being executed as part of
  a substitution transition. Communication happens via messages, not polling.
  """

  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Runtime.ModuleReference

  @typedoc "Child enactment identifier (typically a PID)"
  @type child_id() :: pid() | term()

  @typedoc "Token marking for a place"
  @type marking() :: %{place: String.t(), tokens: term()}

  @doc """
  Resolve a module reference to a concrete Module definition.

  ## When
  - Called when substitution transition becomes enabled
  - Before child enactment starts

  ## Parameters
  - `manager`: The manager instance
  - `module_ref`: Module reference to resolve
  - `options`: Runtime options (enactment_id, etc.)

  ## Returns
  - `{:ok, module}`: Successfully resolved
  - `{:error, reason}`: Resolution failed

  ## Example
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
  Start a child enactment.

  The child enactment will send messages back to the parent when:
  - Initialization completes: `{:child_enactment_ready, child_id}`
  - Execution completes: `{:child_enactment_completed, child_id, output_marking}`
  - Execution fails: `{:child_enactment_failed, child_id, reason}`

  ## When
  - Called after module resolved
  - After input tokens prepared from socket assignments

  ## Parameters
  - `manager`: The manager instance
  - `module`: The module to execute
  - `initial_marking`: Initial tokens for input port places
  - `options`: Execution options
    - `:parent_pid` (required) - Parent enactment PID for sending messages
    - `:parent_enactment_id` - Parent enactment ID for context
    - `:parent_transition` - Name of substitution transition

  ## Returns
  - `{:ok, child_id}`: Child enactment started, will send messages to parent
  - `{:error, reason}`: Failed to start

  ## Example
      {:ok, child_id} = SubFlowManager.start_child_enactment(
        manager,
        auth_module,
        [%{place: "credentials_in", tokens: creds}],
        parent_pid: self(),
        parent_enactment_id: "parent_123",
        parent_transition: "authenticate"
      )

      # Later, parent receives:
      receive do
        {:child_enactment_completed, ^child_id, output_marking} ->
          # Apply output tokens to parent marking
          apply_outputs(output_marking, ...)
      end
  """
  @spec start_child_enactment(t(), Module.t(), [marking()], Keyword.t()) ::
    {:ok, child_id()} | {:error, term()}
  def start_child_enactment(manager, module, initial_marking, options)

  @doc """
  Get current state of a child enactment (optional, for debugging).

  This is NOT for waiting/polling. Parent should use message-based waiting.

  ## When
  - Called for debugging or monitoring purposes only

  ## Parameters
  - `manager`: The manager instance
  - `child_id`: The child enactment identifier

  ## Returns
  - `{:ok, state_info}`: Current state information
  - `{:error, :not_found}`: Child enactment not found

  ## Example
      {:ok, info} = SubFlowManager.get_child_state(manager, child_id)
      # info: %{status: :running, marking: {...}, ...}
  """
  @spec get_child_state(t(), child_id()) ::
    {:ok, map()} | {:error, term()}
  def get_child_state(manager, child_id)
end
```

---

## Message Protocol

### Messages Sent by Child Enactment

```elixir
# 1. Child enactment initialized and ready
{:child_enactment_ready, child_id}

# 2. Child enactment completed successfully
{:child_enactment_completed, child_id, output_marking}
# where output_marking is:
# [
#   %{place: "success_out", tokens: %{user_id: 123}},
#   %{place: "failure_out", tokens: []}
# ]

# 3. Child enactment failed
{:child_enactment_failed, child_id, reason}
# where reason is:
# - {:deadlock, marking} - No enabled transitions
# - {:error_in_action, transition, error} - Action failed
# - {:timeout, duration} - Execution timeout
```

### Parent Enactment Message Handling

```elixir
defmodule ColouredFlow.Runner.Enactment do
  def handle_info({:child_enactment_completed, child_id, output_marking}, state) do
    # Find the substitution transition associated with this child
    case Map.get(state.active_children, child_id) do
      nil ->
        # Unknown child, ignore
        {:noreply, state}

      %{transition: transition, awaiting: true} ->
        # Apply output tokens to parent marking
        new_marking = apply_child_outputs(
          output_marking,
          transition.socket_assignments,
          state.marking
        )

        # Remove from active children
        new_children = Map.delete(state.active_children, child_id)

        # Continue enactment execution
        new_state = %{state |
          marking: new_marking,
          active_children: new_children
        }

        {:noreply, new_state}
    end
  end

  def handle_info({:child_enactment_failed, child_id, reason}, state) do
    # Handle child failure
    case Map.get(state.active_children, child_id) do
      nil ->
        {:noreply, state}

      %{transition: transition} ->
        # Log error, potentially mark failure place, etc.
        Logger.error("Child enactment failed: #{inspect(reason)}")

        # Remove from active children
        new_children = Map.delete(state.active_children, child_id)

        # Optionally: add failure token to a failure place
        # This allows parent CPN to handle child failure as part of workflow

        {:noreply, %{state | active_children: new_children}}
    end
  end
end
```

---

## Token Sharing Detailed Design

### Input Token Flow (Parent → Child)

```elixir
defmodule ColouredFlow.Runner.Enactment do
  defp prepare_child_input_marking(transition, parent_marking, module) do
    # Get input and I/O port places from module
    input_ports = Module.input_ports(module)  # Returns input + io ports

    Enum.map(input_ports, fn port_place ->
      # Find socket assignment for this port
      socket_assignment = Enum.find(
        transition.socket_assignments,
        &(&1.port == port_place.name)
      )

      # Get tokens from parent marking at socket place
      socket_tokens = get_tokens_from_marking(
        parent_marking,
        socket_assignment.socket
      )

      # Create initial marking for child port place
      %{place: port_place.name, tokens: socket_tokens}
    end)
  end
end
```

**Token Copy Semantics**:
- **Copy, not move**: Tokens are copied from parent to child
- **Consumption**: Parent socket tokens are consumed when transition fires
- **Independence**: Child has its own copy, modifications don't affect parent

### Output Token Flow (Child → Parent)

```elixir
defmodule ColouredFlow.Runner.Enactment do
  defp apply_child_outputs(child_output_marking, socket_assignments, parent_marking) do
    Enum.reduce(child_output_marking, parent_marking, fn output, marking ->
      # Find corresponding socket assignment
      socket_assignment = Enum.find(
        socket_assignments,
        &(&1.port == output.place)
      )

      # Add tokens from child output port to parent socket place
      add_tokens_to_marking(
        marking,
        socket_assignment.socket,
        output.tokens
      )
    end)
  end
end
```

**Token Production Semantics**:
- **Copy**: Tokens from child output ports are copied to parent sockets
- **Addition**: New tokens are added to parent marking
- **Completion**: Only happens after child reports completion

### I/O Port Places

For **bidirectional (I/O) ports**, tokens flow both ways:

```elixir
# Before child starts: Copy from parent socket → child I/O port
initial_marking = [
  %{place: "shared_state", tokens: %{counter: 0}}
]

# After child completes: Copy from child I/O port → parent socket
output_marking = [
  %{place: "shared_state", tokens: %{counter: 5}}
]

# Parent socket updated with new value
```

**I/O Semantics**:
- Input phase: Consume from parent socket, copy to child I/O port
- Output phase: Copy from child I/O port, produce to parent socket
- Net effect: Bidirectional data flow

---

## Complete Example with Message-Based Flow

```elixir
defmodule ColouredFlow.Runner.Enactment do
  @doc """
  Handle substitution transition firing with message-based child enactment.
  """
  def handle_transition_fire(%Transition{subst: subst} = transition, state)
      when not is_nil(subst) do

    with(
      # 1. Resolve module
      {:ok, module} <-
        SubFlowManager.resolve_module(
          state.subflow_manager,
          subst,
          enactment_id: state.id
        ),

      # 2. Prepare input tokens
      input_marking = prepare_child_input_marking(transition, state.marking, module),

      # 3. Start child enactment
      {:ok, child_id} <-
        SubFlowManager.start_child_enactment(
          state.subflow_manager,
          module,
          input_marking,
          parent_pid: self(),  # ← Will receive messages
          parent_enactment_id: state.id,
          parent_transition: transition.name
        )
    ) do
      # 4. Track active child
      new_children = Map.put(
        state.active_children,
        child_id,
        %{transition: transition, started_at: System.monotonic_time()}
      )

      # 5. Consume input tokens from parent marking
      new_marking = consume_input_tokens(
        state.marking,
        transition.socket_assignments,
        module
      )

      # Return updated state
      # Parent will receive {:child_enactment_completed, ...} message later
      {:ok, %{state |
        active_children: new_children,
        marking: new_marking
      }}
    else
      {:error, reason} ->
        {:error, {:substitution_transition_failed, reason}}
    end
  end

  # Message handler: Child completed
  def handle_info({:child_enactment_completed, child_id, output_marking}, state) do
    case Map.pop(state.active_children, child_id) do
      {nil, _} ->
        # Unknown child
        {:noreply, state}

      {child_info, remaining_children} ->
        # Apply output tokens
        new_marking = apply_child_outputs(
          output_marking,
          child_info.transition.socket_assignments,
          state.marking
        )

        # Continue enactment (may enable new transitions)
        new_state = %{state |
          marking: new_marking,
          active_children: remaining_children
        }

        # Check for newly enabled transitions
        new_state = compute_enabled_transitions(new_state)

        {:noreply, new_state}
    end
  end

  # Message handler: Child failed
  def handle_info({:child_enactment_failed, child_id, reason}, state) do
    case Map.pop(state.active_children, child_id) do
      {nil, _} ->
        {:noreply, state}

      {child_info, remaining_children} ->
        Logger.error("""
        Child enactment failed:
          Transition: #{child_info.transition.name}
          Reason: #{inspect(reason)}
        """)

        # Option 1: Fail parent enactment
        {:stop, {:child_enactment_failed, reason}, state}

        # Option 2: Add failure token to allow workflow to handle it
        # failure_marking = %{
        #   place: "#{child_info.transition.name}_failed",
        #   tokens: %{reason: reason}
        # }
        # new_marking = add_tokens_to_marking(state.marking, failure_marking)
        # {:noreply, %{state | marking: new_marking, active_children: remaining_children}}
    end
  end

  defp consume_input_tokens(marking, socket_assignments, module) do
    input_ports = Module.input_ports(module)

    Enum.reduce(input_ports, marking, fn port_place, acc_marking ->
      socket = find_socket_for_port(socket_assignments, port_place.name)
      tokens = get_tokens_from_marking(acc_marking, socket)

      # Remove tokens from parent socket place
      remove_tokens_from_marking(acc_marking, socket, tokens)
    end)
  end

  defp apply_child_outputs(output_marking, socket_assignments, parent_marking) do
    Enum.reduce(output_marking, parent_marking, fn output, acc_marking ->
      socket = find_socket_for_port(socket_assignments, output.place)

      # Add tokens to parent socket place
      add_tokens_to_marking(acc_marking, socket, output.tokens)
    end)
  end
end
```

---

## Advantages of This Design

### 1. Message-Based (No Polling)
✅ Efficient - No CPU waste on polling
✅ Reactive - Immediate response to child completion
✅ Scalable - Can handle many children without performance degradation
✅ Idiomatic - Standard Elixir/OTP pattern

### 2. No Direct Cancellation (Token Control)
✅ Preserves Petri Net semantics
✅ Predictable behavior
✅ Testable workflow logic
✅ Child enactments are autonomous

### 3. Clear Token Sharing Semantics
✅ Explicit input/output token flow
✅ Socket assignments define the mapping
✅ Copy semantics (not shared state)
✅ Supports I/O (bidirectional) ports

### 4. Child Enactment Terminology
✅ Accurate - Modules execute as enactments
✅ Clear - Parent-child relationship explicit
✅ Consistent - Matches ColouredFlow concepts

---

## Questions for Confirmation

1. ✅ **Naming**: "child enactment" vs "sub enactment"?
   - My recommendation: **child enactment**

2. ✅ **Message-based**: Agree with message notification instead of polling?

3. ✅ **No cancellation**: Agree that termination should be token-based?

4. ✅ **Token sharing**: Is the copy semantics clear?
   - Input: Copy from parent socket → child input port
   - Output: Copy from child output port → parent socket

5. **Additional questions**:
   - Should we support synchronous waiting (block until child completes)?
   - Should we support multiple concurrent children per substitution transition?
   - How to handle child timeout? (Add timeout token to child? Monitor and log?)

Please confirm or suggest adjustments!
