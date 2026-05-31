defmodule ColouredFlowDashboardWeb.Views.BindingCandidate do
  @moduledoc """
  Wire-shape of a single candidate binding row rendered in the enactment
  detail Debug tab.

  Produced by `ColouredFlowDashboard.BindingInspector.inspect/3` for the
  `:inspect_transition` command. Each candidate represents one combined
  binding the runner can compute against the current marking — labelled
  `:enabled`, `:rejected_by_guard`, `:rejected_by_arc_eval`, or
  `:rejected_by_marking` per the inspector's classification rules. `reason`
  is `nil` for enabled rows and carries a short human-readable string for
  the three rejection kinds.
  """

  use Musubi.State

  state do
    field :transition, String.t()
    field :binding_summary, String.t()

    field :guard_status,
          :enabled | :rejected_by_guard | :rejected_by_arc_eval | :rejected_by_marking

    field :reason, String.t() | nil
  end
end
