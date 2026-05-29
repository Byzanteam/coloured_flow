defmodule ColouredFlowDashboardWeb.Views.TransitionDebugInfo do
  @moduledoc """
  Rollup of `BindingCandidate` totals returned by the `:inspect_transition`
  command. Rendered above the candidate table in the enactment detail Debug
  tab.

  `candidates_count == enabled_count + rejected_by_guard_count +
  rejected_by_marking_count` for every well-formed inspector reply.
  """

  use Musubi.State

  state do
    field :transition, String.t()
    field :candidates_count, integer()
    field :enabled_count, integer()
    field :rejected_by_guard_count, integer()
    field :rejected_by_marking_count, integer()
  end
end
