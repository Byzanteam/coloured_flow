defmodule ColouredFlowDashboardWeb.Views.WorkitemRow do
  @moduledoc """
  Wire-shape of a single live workitem row rendered in the operator inbox.

  Built either from a `ColouredFlow.Runner.Storage.Schemas.Workitem` row (the
  cursor-paged seed loaded on `mount/2`) or from a runtime
  `ColouredFlow.Runner.Enactment.Workitem` struct delivered through the
  `cf:inbox` telemetry bridge (`{:cf_event, %Event{}}` messages).

  Timestamps are surfaced as ISO8601 strings so the SPA never sees raw
  `DateTime`/`NaiveDateTime` structs; only the live state subset
  (`#{inspect(ColouredFlow.Runner.Enactment.Workitem.__live_states__())}`)
  is ever streamed.

  `output_vars` is the flat list of free-variable names (`Variable.name()`
  serialised as strings) the operator must supply when completing this
  workitem. Inferred at row construction from the transition's
  `Action.outputs` — auto-populated by `ColouredFlow.Builder.SetActionOutputs`
  as `output_arc_vars MINUS input_arc_vars MINUS constants`. Empty list when
  the transition has no free variables (terminal step / pure side effect).
  """

  use Musubi.State

  state do
    field :id, String.t()
    field :enactment_id, String.t()
    field :flow_topic_id, String.t() | nil
    field :transition, String.t()
    field :state, :enabled | :started
    field :binding_summary, String.t()
    field :output_vars, list(String.t())
    field :enabled_at, String.t()
    field :updated_at, String.t()
  end
end
