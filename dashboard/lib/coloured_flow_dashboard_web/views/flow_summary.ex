defmodule ColouredFlowDashboardWeb.Views.FlowSummary do
  @moduledoc """
  Wire-shape of a single flow row rendered on the `/flows` catalog page.

  Built from a `ColouredFlow.Runner.Storage.Schemas.Flow` row plus a rollup
  over the flow's enactments (live count, last started timestamp, recent
  enactment ids + states). `id` is the storage row's UUID — the catalog uses
  it as the stream item key AND as the `:start_enactment` command payload.

  `recent_enactments` is capped to the 3 most recently-started enactments so
  the catalog grid can render short-id links without paginating.
  `enactments` carries the full per-flow enactment list (newest first) so the
  per-flow detail page at `/flows/:flow_id` can render every row.

  `diagram` mirrors the wire shape used by `EnactmentDetailStore` so the
  per-flow detail page can render the same NetDiagram component with zero
  marking data (tokens_count = 0, no glow, no firing pulse).
  """

  use Musubi.State

  state do
    field :id, String.t()
    field :name, String.t()
    field :version, String.t()
    field :place_count, integer()
    field :transition_count, integer()
    field :live_enactments, integer()
    field :last_started_at, String.t() | nil

    field :recent_enactments,
          list(ColouredFlowDashboardWeb.Views.FlowEnactmentEntry.t())

    field :enactments,
          list(ColouredFlowDashboardWeb.Views.FlowEnactmentEntry.t())

    field :diagram, ColouredFlowDashboardWeb.Views.NetDiagram.t() | nil
  end
end
