defmodule ColouredFlowDashboardWeb.Views.NetDiagram do
  @moduledoc """
  Wire-shape backing the left-pane React Flow net diagram on the enactment
  detail page.

  Derived once at mount from `ColouredFlowDashboard.TelemetryBridge.lookup_cpnet/2`
  (the cpnet cache populated lazily by the bridge). Refreshed in the store's
  `:cf_event` handler when the cpnet cache was empty at mount time, mirroring
  the `transitions` refresh pattern.

  Token counts on `places[*]` mirror the canonical `MarkingRow` shape so the
  SPA never has to recompute them — the store keeps a `place ↦ MarkingRow`
  table and writes the latest counts into the diagram payload as marking events
  arrive.

  Transition rollup fields (`enabled_count`, `rejected_by_*`) mirror
  `TransitionDebugInfo`. Initially zero; updated when a `*_workitems_stop`
  event for that transition is processed (best-effort live count from the
  workitem stream, not a guard-replay inspection).

  `arcs[*].orientation` is one of `:p_to_t` (place → transition, an incoming
  arc) or `:t_to_p`. Atoms pass through Musubi's wire as strings.
  """

  use Musubi.State

  alias ColouredFlowDashboardWeb.Views.ColourSetDef
  alias ColouredFlowDashboardWeb.Views.NetDiagramArc
  alias ColouredFlowDashboardWeb.Views.NetDiagramPlace
  alias ColouredFlowDashboardWeb.Views.NetDiagramTransition

  state do
    field :places, list(NetDiagramPlace.t())
    field :transitions, list(NetDiagramTransition.t())
    field :arcs, list(NetDiagramArc.t())
    field :colour_sets, list(ColourSetDef.t())
  end
end
