defmodule ColouredFlowDashboardWeb.UserSocket do
  @moduledoc """
  Musubi socket adapter for the ColouredFlow Dashboard.

  `roots:` advertises the root stores the SPA may mount via
  `connection.mountStore({module: "...", id: "..."})`. `FlowCatalogStore`
  lands in a later phase.
  """

  use Musubi.Socket,
    roots: [
      ColouredFlowDashboardWeb.Stores.InboxStore,
      ColouredFlowDashboardWeb.Stores.EnactmentDetailStore
    ]
end
