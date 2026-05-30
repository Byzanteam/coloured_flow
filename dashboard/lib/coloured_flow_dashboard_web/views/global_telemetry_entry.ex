defmodule ColouredFlowDashboardWeb.Views.GlobalTelemetryEntry do
  @moduledoc """
  Wire-shape of a single row in the global telemetry feed at `/telemetry`.

  Synthesised inside `ColouredFlowDashboardWeb.Stores.TelemetryFeedStore` from
  `ColouredFlowDashboard.TelemetryBridge.Event` broadcasts on the
  `cf:telemetry` topic.

  Distinct from `#{inspect(ColouredFlowDashboardWeb.Views.TelemetryEntry)}` —
  the per-enactment entry shape, which is rendered on the detail page's
  Telemetry tab. The global feed additionally carries `enactment_id` /
  `flow_id` columns and emits the raw bridge `event` string (e.g.
  `"complete_workitems_stop"`) rather than a humanised summary.

  `id` is minted at insert time via `System.unique_integer/1`; the bridge
  does not attach a per-event identifier.

  `measurements_json` / `metadata_json` are pre-encoded with `JSON.encode!/1`
  so the SPA can render the expanded payload without re-walking the
  Elixir-side structs.
  """

  use Musubi.State

  state do
    field :id, String.t()
    field :event, String.t()
    field :enactment_id, String.t() | nil
    field :flow_id, String.t() | nil
    field :occurred_at, String.t()
    field :seq, integer()
    field :measurements_json, String.t()
    field :metadata_json, String.t()
    field :summary, String.t()
  end
end
