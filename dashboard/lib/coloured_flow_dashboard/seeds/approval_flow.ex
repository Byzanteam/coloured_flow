defmodule ColouredFlowDashboard.Seeds.ApprovalFlow do
  @moduledoc """
  Demo flow that backs the operator inbox + outputs drawer end-to-end story.

  Two places (`:pending`, `:decided`) and one transition (`:approve`). The
  transition consumes the single token in `:pending`, leaves the operator
  with two free variables (`verdict` and `note`) that must be supplied via
  the outputs drawer, and produces one token of type `outcome` in
  `:decided`.

  Both free variables use `binary()` colour sets so the JSON-only drawer
  (M2b) can round-trip values without atom marshaling. M5 replaces the
  textarea with a structured form and may upgrade `verdict` to an atom
  union — kept as binary here so the demo works on dashboards that have
  not yet shipped the structured form.

  `Action.outputs` is auto-populated by `ColouredFlow.Builder.SetActionOutputs`
  as `output_arc_vars MINUS input_arc_vars MINUS constants`, so the
  drawer's `output_vars` hint surfaces `["note", "verdict"]` (sorted) for
  every workitem the runner produces from this flow.
  """

  use ColouredFlow.DSL

  name "Approval Demo"
  version "1.0.0"

  # The Place validator rejects bare built-in types (`:unit`, `:binary`, ...)
  # as place colour-set references; every place colour set must come from a
  # `colset` declaration. `trigger` wraps `boolean()` so the `:pending` place
  # holds one `true` token to enable `:approve`.
  colset trigger_t() :: boolean()
  colset verdict_t() :: binary()
  colset note_t() :: binary()
  colset outcome() :: {verdict_t(), note_t()}

  var t :: trigger_t()
  var verdict :: verdict_t()
  var note :: note_t()

  place :pending, :trigger_t
  place :decided, :outcome

  initial_marking :pending, ~MS[true]

  transition :approve do
    input :pending, bind({1, t})
    output :decided, {1, {verdict, note}}
  end
end
