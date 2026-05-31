defmodule ColouredFlowDashboardWeb.Views.VersionRange do
  @moduledoc """
  Wire-shape exposing the inclusive `[min, max]` version window the timeline
  scrubber may move across.

  `min` is the version of the latest persisted snapshot (the floor below
  which we cannot reconstruct markings without keeping older snapshots).
  `max` is the latest known occurrence position observed by the dashboard
  via PubSub events.
  """

  use Musubi.State

  state do
    field :min, integer()
    field :max, integer()
  end
end
