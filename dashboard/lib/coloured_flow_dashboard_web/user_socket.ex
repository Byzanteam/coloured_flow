defmodule ColouredFlowDashboardWeb.UserSocket do
  @moduledoc """
  Musubi socket placeholder for the ColouredFlow Dashboard.

  Phase 7 onward replaces `roots: []` with the dashboard's actual root stores
  (`InboxStore`, `EnactmentDetailStore`, `FlowCatalogStore`). For now this
  module exists only so the endpoint can wire `/socket` to a real
  `use Musubi.Socket` adapter and so future phases have a single edit point.
  """

  use Musubi.Socket, roots: []
end
