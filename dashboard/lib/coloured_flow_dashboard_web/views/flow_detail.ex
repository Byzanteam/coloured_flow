defmodule ColouredFlowDashboardWeb.Views.FlowDetail do
  @moduledoc """
  Wire-shape returned by `FlowCatalogStore`'s `:fetch_flow_detail` command.

  Carries the heavy per-flow payload the `/flows/:flow_id` detail page needs
  (full enactments list + static, marking-free NetDiagram) so the catalog
  stream stays light. Counts mirror `FlowSummary` so the detail page can
  render header chips without joining against the stream snapshot.
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

    field :enactments,
          list(ColouredFlowDashboardWeb.Views.FlowEnactmentEntry.t())

    field :diagram, ColouredFlowDashboardWeb.Views.NetDiagram.t()
  end
end
