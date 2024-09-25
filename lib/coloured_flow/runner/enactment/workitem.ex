defmodule ColouredFlow.Runner.Enactment.Workitem do
  @moduledoc """
  The workitem in the coloured_flow runner.
  """

  use TypedStructor

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

  Among these states, `enabled`, `allocated`, and `started` are the `live` states.

  > #### INFO {: .info}
  > Note: The workitem should not be *failed*, because the failure should be handled by handlers.

  ## References
  [^1]: Workflow Patterns: The Definitive Guide.pdf, p. 293.

  [^2]: Modern Business Process Automation YAWL and its Support Environment.pdf, p. 249

  """
  @type state() :: :enabled | :allocated | :started | :completed | :withdrawn

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :id, Ecto.UUID.t(),
      doc: """
      The unique identifier of the workitem.
      """

    field :state, state(),
      doc: """
      The state of the workitem, see `t:ColouredFlow.Runner.Workitem.state/0`.
      """

    field :binding_element, ColouredFlow.Enactment.BindingElement.t(),
      doc: """
      The binding element for the workitem.
      """
  end
end
