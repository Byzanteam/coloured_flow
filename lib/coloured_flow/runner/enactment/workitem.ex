defmodule ColouredFlow.Runner.Enactment.Workitem do
  @moduledoc """
  The workitem in the coloured_flow runner.
  """

  use TypedStructor

  @type id() :: Ecto.UUID.t()

  @transitions [
    # normal
    {:enabled, :allocate, :allocated},
    {:allocated, :start, :started},
    {:started, :complete, :completed},
    # exception
    {:allocated, :reoffer_a, :enabled},
    {:started, :reoffer_s, :enabled},
    {:started, :reallocate_s, :allocated},
    # system
    {:enabled, :withdraw_o, :withdrawn},
    {:allocated, :withdraw_a, :withdrawn},
    {:started, :withdraw_s, :withdrawn}
  ]

  @type in_progress_state() :: :allocated | :started
  @type live_state() :: :enabled | in_progress_state()
  @type completed_state() :: :completed | :withdrawn

  @typedoc """
  The state of the workitem. [^1] [^2]

  ```mermaid
  stateDiagram-v2
      direction LR

      %% normal
      [*] --> enabled: *create
      enabled --> allocated: *allocate
      allocated --> started: *start
      started --> completed: *complete
      completed --> [*]

      %% exception
      allocated --> enabled: reoffer-a
      started --> enabled: reoffer-s
      started --> allocated: reallocate−s

      %% system
      enabled --> withdrawn: withdraw-o
      allocated --> withdrawn: withdraw-a
      started --> withdrawn: withdraw-s
      withdrawn --> [*]
  ```

  > Note: The suffix `-a` indicates the workitem is `allocated`,
  > and the suffix `-s` indicates the workitem is `started`.
  > `*` indicates the normal state transition path.

  | State | Description |
  | --- | --- |
  | `enabled` | The workitem has been enabled to resources. |
  | `allocated` | The workitem has been allocated to a resource. |
  | `started` | The workitem has been started to handle. |
  | `completed` | The workitem has been completed normally. |
  | `withdrawn` | The workitem has been withdrawn, perhaps because other workitem has been allocated. |

  Among these states, `enabled`, `allocated`, and `started` are the live states.
  Specifically, `allocated` and `started` are the `in-progress` states,
  meaning the workitem is being handled by resources. `completed` and `withdrawn`
  are the `completed` states.


  > #### INFO {: .info}
  > Note: The workitem should not be *failed*, because the failure should be handled by handlers.

  ## Available Transitions

  | From | Transition | To |
  | --- | --- | --- |
  #{Enum.map_join(@transitions, "\n", fn {from, transition, to} -> "| `#{from}` | `#{transition}` | `#{to}` |" end)}

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
  def __in_progress_states__, do: ~w[allocated started]a

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
  The valid transitions of the workitem, represented as a list of a `{from, transition, to}` tuple.

  For example, `{:enabled, :allocate, :allocated}` means the workitem can be `allocated`
  when it is `enabled` by the `allocate` transition.

  See `t:state/0` for the available transitions.
  """
  @spec __transitions__() ::
          [
            unquote(
              @transitions
              |> Enum.map(fn t -> Macro.escape(t) end)
              |> ColouredFlow.Types.make_sum_type()
            )
          ]
  def __transitions__, do: @transitions
end
