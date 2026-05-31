defmodule ColouredFlowDashboardWeb.UserSocket do
  @moduledoc """
  Musubi socket adapter for the ColouredFlow Dashboard.

  `roots:` advertises the root stores the SPA may mount via
  `connection.mountStore({module: "...", id: "..."})`.
  """

  use Musubi.Socket,
    roots: [
      ColouredFlowDashboardWeb.Stores.InboxStore,
      ColouredFlowDashboardWeb.Stores.EnactmentDetailStore,
      ColouredFlowDashboardWeb.Stores.EnactmentListStore,
      ColouredFlowDashboardWeb.Stores.FlowCatalogStore,
      ColouredFlowDashboardWeb.Stores.TelemetryFeedStore
    ]
end
