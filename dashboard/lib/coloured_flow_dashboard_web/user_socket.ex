defmodule ColouredFlowDashboardWeb.UserSocket do
  @moduledoc """
  Musubi socket adapter for the ColouredFlow Dashboard.

  `roots:` advertises the root stores the SPA may mount via
  `connection.mountStore({module: "...", id: "..."})`. Additional roots
  (`EnactmentDetailStore`, `FlowCatalogStore`) land in later phases.
  """

  use Musubi.Socket,
    roots: [
      ColouredFlowDashboardWeb.Stores.InboxStore
    ]
end
