defmodule ColouredFlowDashboardWeb.Views.FlowEnactmentEntry do
  @moduledoc """
  Compact recent-enactment row embedded in `FlowSummary.recent_enactments`.

  Carries just enough state for the catalog card to render a clickable
  short-id link with a colour-coded lifecycle dot; the full detail surface
  is the per-enactment detail page at `/enactments/:id`.
  """

  use Musubi.State

  state do
    field :id, String.t()
    field :state, :running | :exception | :terminated
    field :inserted_at, String.t()
  end
end
