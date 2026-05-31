defmodule ColouredFlowDashboardWeb.Views.ReplayState do
  @moduledoc """
  Wire-shape signalling that the enactment detail page is currently rendering
  a derived (read-only) marking at a prior version. `nil` on the parent
  `EnactmentSummary.replay_state` field means live mode.

  `derived_at` is an ISO-8601 timestamp pinning when the derivation ran so
  the UI can show staleness if the operator lingers.
  """

  use Musubi.State

  state do
    field :version, integer()
    field :derived_at, String.t()
  end
end
