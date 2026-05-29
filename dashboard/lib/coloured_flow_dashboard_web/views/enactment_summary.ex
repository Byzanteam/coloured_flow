defmodule ColouredFlowDashboardWeb.Views.EnactmentSummary do
  @moduledoc """
  Header rollup rendered above the enactment-detail tabs.

  `state` mirrors `ColouredFlow.Runner.Enactment` lifecycle states
  (`:running | :exception | :terminated`). When the GenServer is up we read
  it via a single peek (see store mount); when it has shut down (terminated
  / exception) we treat the storage row's `state` column as the source of
  truth instead.
  """

  use Musubi.State

  state do
    field :enactment_id, String.t()
    field :flow_topic_id, String.t() | nil
    field :state, :running | :exception | :terminated
    field :version, integer()
    field :markings_count, integer()
    field :workitems_count, integer()
    field :last_occurrence_at, String.t() | nil
  end
end
