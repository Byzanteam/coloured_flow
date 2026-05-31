defmodule ColouredFlowDashboardWeb.Views.FlowSummary do
  @moduledoc """
  Lightweight wire-shape of a single flow row rendered on the `/flows`
  catalog grid.

  Built from a `ColouredFlow.Runner.Storage.Schemas.Flow` row plus a small
  rollup over the flow's enactments (live count, last started timestamp,
  the 3 most recent enactment ids + states, total enactment count). `id` is
  the storage row's UUID — the catalog uses it as the stream item key AND
  as the `:start_enactment` / `:fetch_flow_detail` command payloads.

  Detail-page payload (full enactments list + static NetDiagram) is fetched
  on demand via the `:fetch_flow_detail` command so the catalog stream's
  per-row footprint does not grow with history.
  """

  use Musubi.State

  state do
    field :id, String.t()
    field :name, String.t()
    field :version, String.t()
    field :place_count, integer()
    field :transition_count, integer()
    field :live_enactments, integer()
    field :total_enactments, integer()
    field :last_started_at, String.t() | nil

    field :recent_enactments,
          list(ColouredFlowDashboardWeb.Views.FlowEnactmentEntry.t())
  end
end
