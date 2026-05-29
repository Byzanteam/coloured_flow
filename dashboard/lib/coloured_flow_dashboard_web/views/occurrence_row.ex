defmodule ColouredFlowDashboardWeb.Views.OccurrenceRow do
  @moduledoc """
  Wire-shape of a single occurrence (fired binding element) row rendered in
  the enactment detail Occurrences tab.

  The id is synthesised from `"<enactment_id>-<step_number>"` because the
  occurrence storage row is keyed by the composite `(enactment_id, step_number)`
  primary key — there is no opaque uuid. `binding_summary` mirrors the inbox
  inspector format; `outputs_summary` carries the free-binding the operator
  supplied (or the `:complete_workitems_stop` payload's bridge-side outputs
  digest).
  """

  use Musubi.State

  state do
    field :id, String.t()
    field :step_number, integer()
    field :transition, String.t()
    field :binding_summary, String.t()
    field :occurred_at, String.t()
    field :outputs_summary, String.t()
  end
end
