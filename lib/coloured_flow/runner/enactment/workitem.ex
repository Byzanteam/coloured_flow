defmodule ColouredFlow.Runner.Enactment.Workitem do
  @moduledoc """
  The workitem in the coloured_flow runner.
  """

  use TypedStructor

  @type id() :: Ecto.UUID.t()

  @transitions [
    # normal
    {:enabled, :start, :started},
    {:started, :complete, :completed},
    {:enabled, :complete_e, :completed},
    # exception
    {:started, :reoffer_s, :enabled},
    # system
    {:started, :withdraw_s, :withdrawn},
    {:enabled, :withdraw, :withdrawn}
  ]

  @type transition() ::
          unquote(
            @transitions
            |> Enum.map(fn t -> Macro.escape(t) end)
            |> ColouredFlow.Types.make_sum_type()
          )

  @type transition_action() ::
          unquote(
            @transitions
            |> Enum.map(&elem(&1, 1))
            |> ColouredFlow.Types.make_sum_type()
          )

  @type in_progress_state() :: :started
  @type live_state() :: :enabled | in_progress_state()
  @type completed_state() :: :completed | :withdrawn

  @typedoc """
  The state of the workitem. [^1] [^2]

  ```mermaid
  stateDiagram-v2
      direction LR

      %% normal
      [*] --> enabled: *create
      enabled --> started: *start
      started --> completed: *complete
      enabled --> completed: complete-e
      completed --> [*]

      %% exception
      started --> enabled: reoffer

      %% system
      enabled --> withdrawn: withdraw
      started --> withdrawn: withdraw-s
      withdrawn --> [*]
  ```

  > Note: The suffix `-e` indicates the workitem is `enabled`,
  > and the suffix `-s` indicates the workitem is `started`.
  > `*` indicates the normal state transition path.

  | State | Description |
  | --- | --- |
  | `enabled` | The workitem has been enabled to resources. |
  | `started` | The workitem has been started to handle. |
  | `completed` | The workitem has been completed normally. |
  | `withdrawn` | The workitem has been withdrawn, perhaps because other workitem has been started. |

  Among these states, `enabled` and `started` are the live states.
  Specifically, `started` are the `in-progress` states,
  meaning the workitem is being handled by resources. `completed` and `withdrawn`
  are the `completed` states.


  > #### INFO {: .info}
  > Note: The workitem should not be *failed*, because the failure should be handled by handlers.

  ## Available Transitions

  | From | Action | To |
  | --- | --- | --- |
  #{Enum.map_join(@transitions, "\n", fn {from, action, to} -> "| `#{from}` | `#{action}` | `#{to}` |" end)}

  ## References
  [^1]: Workflow Patterns: The Definitive Guide.pdf, p. 293.

  [^2]: Modern Business Process Automation YAWL and its Support Environment.pdf, p. 249

  """
  @type state() :: live_state() | completed_state()

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    parameter :state

    field :id, id(),
      doc: """
      The unique identifier of the workitem.
      """

    field :state, state,
      doc: """
      The state of the workitem, see `t:ColouredFlow.Runner.Workitem.state/0`.
      """

    field :binding_element, ColouredFlow.Enactment.BindingElement.t(),
      doc: """
      The binding element for the workitem.
      """
  end

  @type t() :: t(state())

  @doc """
  The live states of the workitem. See more at `t:state/0`.
  """
  @spec __live_states__() :: [live_state()]
  def __live_states__, do: ~w[enabled]a ++ __in_progress_states__()

  @doc """
  The in-progress states of the workitem. See more at `t:state/0`.
  """
  @spec __in_progress_states__() :: [in_progress_state()]
  def __in_progress_states__, do: ~w[started]a

  @doc """
  The completed states of the workitem. See more at `t:state/0`.
  """
  @spec __completed_states__() :: [completed_state()]
  def __completed_states__, do: ~w[completed withdrawn]a

  @doc """
  The states of the workitem. See more at `t:state/0`.
  """
  @spec __states__() :: [state()]
  def __states__, do: __live_states__() ++ __completed_states__()

  @doc """
  The valid transitions of the workitem, represented as a list of a `{from, action, to}` tuple.

  For example, `{:enabled, :start, :started}` means the workitem can be
  transitioned to `started` when it is `enabled` by the `start` action.

  See `t:state/0` for the available transitions.
  """
  @spec __transitions__() :: [transition()]
  def __transitions__, do: @transitions
end
