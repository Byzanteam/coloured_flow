defmodule ColouredFlowDashboardWeb.Views.FlowCatalogCounts do
  @moduledoc """
  Header rollup rendered above the flow catalog grid. Same shape contract as
  `ColouredFlowDashboardWeb.Views.InboxCounts` — totals are computed in
  `ColouredFlowDashboardWeb.Stores.FlowCatalogStore` so the SPA never has to
  walk the `:flows` stream to derive its metric strip.
  """

  use Musubi.State

  state do
    field :total_flows, integer()
    field :total_live_enactments, integer()
  end
end
