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
  """

  use Musubi.State

  state do
    field :id, String.t()
    field :enactment_id, String.t()
    field :flow_topic_id, String.t() | nil
    field :transition, String.t()
    field :state, :enabled | :started
    field :binding_summary, String.t()
    field :enabled_at, String.t()
    field :updated_at, String.t()
  end
end
