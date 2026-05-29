defmodule ColouredFlowDashboardWeb.Views.TelemetryEntry do
  @moduledoc """
  Wire-shape of a single telemetry event row rendered in the enactment detail
  Telemetry tab.

  Entries are synthesised inside
  `ColouredFlowDashboardWeb.Stores.EnactmentDetailStore` from
  `ColouredFlowDashboard.TelemetryBridge.Event` broadcasts that match the
  mounted enactment id. The bridge does not attach a per-event id, so the
  store mints one (`"<enactment_id>-<unique>"`) at insert time using a
  monotonic counter; this guarantees the stream's `item_key` never collides
  and the SPA can use it as a React key.

  `payload_json` is the bridge `Event.payload` serialised with `JSON.encode!/1`
  (project convention — no `Jason`). The SPA renders it inside an expandable
  `<pre>` block so operators can drill into the original metadata without the
  store having to know about every event kind.
  """

  use Musubi.State

  state do
    field :id, String.t()
    field :kind, atom()
    field :at, String.t()
    field :summary, String.t()
    field :severity, :info | :warning | :error
    field :payload_json, String.t()
  end
end
