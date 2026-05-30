defmodule ColouredFlowDashboardWeb.Views.EnactmentSummary do
  @moduledoc """
  Header rollup rendered above the enactment-detail tabs.

  `state` mirrors `ColouredFlow.Runner.Enactment` lifecycle states
  (`:running | :exception | :terminated`). When the GenServer is up we read
  it via a single peek (see store mount); when it has shut down (terminated
  / exception) we treat the storage row's `state` column as the source of
  truth instead.

  `last_exception_banner` is the latest enactment-level exception banner
  (`error_banner` from `:enactment_exception` events ONLY — never workitem
  operation halves like `:produce_workitems_exception`). Cleared back to
  `nil` on `:enactment_terminate` so a force-terminated enactment does not
  surface a stale banner.

  `replay_state` is `nil` when the page is showing live state. While the
  M7a timeline scrubber holds an earlier version, the store sets it to
  `%ReplayState{version, derived_at}` so the SPA can swap the Markings tab
  + diagram into the derived view and surface a "REPLAY · vN" chip.

  `version_range` exposes the inclusive `[min, max]` window the scrubber
  is allowed to move across. `min` is the latest snapshot version (the
  floor below which we cannot reconstruct markings without older
  snapshots); `max` is the most recent enactment version observed via
  PubSub events.
  """

  use Musubi.State

  state do
    field :enactment_id, String.t()
    field :flow_topic_id, String.t() | nil
    field :flow_name, String.t() | nil
    field :state, :running | :exception | :terminated
    field :version, integer()
    field :markings_count, integer()
    field :workitems_count, integer()
    field :last_occurrence_at, String.t() | nil
    field :last_exception_banner, String.t() | nil
    field :replay_state, ColouredFlowDashboardWeb.Views.ReplayState.t() | nil
    field :version_range, ColouredFlowDashboardWeb.Views.VersionRange.t()
  end
end
