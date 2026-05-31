defmodule ColouredFlowDashboardWeb.Views.NetDiagramTransition do
  @moduledoc """
  Wire-shape of a single transition node rendered by the React Flow net
  diagram.

  Count fields mirror `TransitionDebugInfo`. The store updates them
  best-effort from live workitem stream events — initially zero, then
  incremented/decremented as `*_workitems_stop` events arrive. A full
  guard-replay rollup is available on-demand via the `:inspect_transition`
  command; the diagram does not call it eagerly.

  `last_fired_at` is the ISO8601 timestamp of the most recent
  `:complete_workitems_stop` event for this transition. The SPA keys a brief
  pulse animation off it.
  """

  use Musubi.State

  state do
    field :name, String.t()
    field :enabled_count, integer()
    field :rejected_by_guard_count, integer()
    field :rejected_by_arc_eval_count, integer()
    field :rejected_by_marking_count, integer()
    field :last_fired_at, String.t() | nil
  end
end
