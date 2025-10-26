defprotocol ColouredFlow.Runtime.SubFlowManager do
  @moduledoc """
  Protocol for managing child enactment (module execution) lifecycle.

  A child enactment is an instance of a module being executed as part of
  a substitution transition. Communication happens via messages, not polling.

  ## Message Protocol

  Child enactments send messages to their parent enactment:

  - `{:child_enactment_ready, child_id}` - Initialization complete
  - `{:child_enactment_completed, child_id, output_marking}` - Execution successful
  - `{:child_enactment_failed, child_id, reason}` - Execution failed

  ## Token Sharing

  Tokens are shared between parent and child through socket assignments:

  - **Input**: Copy from parent socket → child input port (consumed from parent)
  - **Output**: Copy from child output port → parent socket (produced to parent)
  - **I/O**: Bidirectional flow (both input and output)

  ## Example

      # Application startup
      manager = SubFlowManager.Default.new(repo: MyApp.Repo)

      # In enactment
      {:ok, module} = SubFlowManager.resolve_module(
        manager,
        {:module_ref, flow_id: 123, port_specs: [...]},
        enactment_id: "parent_123"
      )

      {:ok, child_id} = SubFlowManager.start_child_enactment(
        manager,
        module,
        initial_marking,
        parent_pid: self(),
        parent_enactment_id: "parent_123"
      )

      # Later receive message
      receive do
        {:child_enactment_completed, ^child_id, output_marking} ->
          # Apply output tokens to parent
      end
  """

  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Runtime.ModuleReference

  @typedoc "Child enactment identifier (typically a PID)"
  @type child_id() :: pid() | term()

  @typedoc "Token marking for a place"
  @type marking() :: %{place: String.t(), tokens: term()}

  @doc """
  Resolve a module reference to a concrete Module definition.

  ## When Called

  - When substitution transition becomes enabled
  - Before child enactment starts

  ## Parameters

  - `manager`: The manager instance (struct implementing this protocol)
  - `module_ref`: Module reference to resolve
  - `options`: Runtime options
    - `:enactment_id` - Parent enactment ID for context
    - Other custom options

  ## Returns

  - `{:ok, module}`: Successfully resolved module
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

  ## When Called

  - After module resolved via `resolve_module/3`
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
        [%{place: "credentials_in", tokens: %{user: "alice"}}],
        parent_pid: self(),
        parent_enactment_id: "parent_123",
        parent_transition: "authenticate"
      )

      # Later, parent receives:
      receive do
        {:child_enactment_completed, ^child_id, output_marking} ->
          # Apply output tokens to parent marking
          apply_outputs(output_marking, socket_assignments, parent_marking)
      end
  """
  @spec start_child_enactment(t(), Module.t(), [marking()], Keyword.t()) ::
          {:ok, child_id()} | {:error, term()}
  def start_child_enactment(manager, module, initial_marking, options)

  @doc """
  Get current state of a child enactment (optional, for debugging).

  This is NOT for waiting/polling. Parent should use message-based waiting.

  ## When Called

  - For debugging or monitoring purposes only
  - Not for normal workflow execution

  ## Parameters

  - `manager`: The manager instance
  - `child_id`: The child enactment identifier

  ## Returns

  - `{:ok, state_info}`: Current state information
    - Map containing: `:status`, `:marking`, `:started_at`, etc.
  - `{:error, :not_found}`: Child enactment not found

  ## Example

      {:ok, info} = SubFlowManager.get_child_state(manager, child_id)
      # info: %{status: :running, marking: %{...}, started_at: ~U[...]}
  """
  @spec get_child_state(t(), child_id()) ::
          {:ok, map()} | {:error, term()}
  def get_child_state(manager, child_id)
end
