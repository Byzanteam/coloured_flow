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

  `output_vars` is the ordered list of
  `ColouredFlowDashboardWeb.Views.OutputVar`s describing the free variables
  the operator must supply when completing this workitem. Resolved at row
  construction by `ColouredFlowDashboard.OutputSchemaBuilder.build/2`; carries
  enough type info for the M5 structured form (Input / Number / Checkbox /
  Select / JSON fallback). Empty list when the transition has no free
  variables (terminal step / pure side effect).

  `enactment_state` mirrors the parent enactment's lifecycle state
  (`:running | :exception | :terminated`). M6 surfaces it on the inbox so
  an operator can spot rows whose enactment cannot make progress (the row
  is still live in the runner, but completing it will hit `:runner_error`).
  Default `:running`; flips to `:exception` when an `:enactment_exception`
  bridge event arrives for the row's enactment.
  """

  use Musubi.State

  alias ColouredFlowDashboardWeb.Views.OutputVar

  state do
    field :id, String.t()
    field :enactment_id, String.t()
    field :flow_topic_id, String.t() | nil
    field :transition, String.t()
    field :state, :enabled | :started
    field :enactment_state, :running | :exception | :terminated
    field :binding_summary, String.t()
    field :output_vars, list(OutputVar.t())
    field :enabled_at, String.t()
    field :updated_at, String.t()
  end
end
