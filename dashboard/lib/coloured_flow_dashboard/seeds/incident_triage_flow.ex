defmodule ColouredFlowDashboard.Seeds.IncidentTriageFlow do
  @moduledoc """
  Second seeded demo flow. Exercises the M5 structured outputs drawer beyond
  the binary-only `ApprovalFlow`: the triage transition's three free
  variables span enum (`severity`), boolean (`acknowledged`), and string
  (`note`) controls, so the drawer renders a native `select`, Kumo `Checkbox`,
  and Kumo `Input` side-by-side.

  Two places (`:pending`, `:triaged`) and one transition (`:triage`). The
  `:pending` place holds a single `alert :: boolean()` token (`true` means
  unresolved). Firing `:triage` consumes that token, binds `severity`,
  `acknowledged`, and `note` via the operator's drawer submission, and
  produces one `{severity, acknowledged, note}` triple in `:triaged`.

  Free variables (`severity`, `acknowledged`, `note`) are auto-populated by
  `ColouredFlow.Builder.SetActionOutputs` because they appear on the
  output-arc but not the input-arc nor the constants list.

  ## Why a second flow?

  ApprovalFlow's `verdict_t` / `note_t` are both `binary()`. The structured
  form has nothing to upgrade beyond two text inputs there. IncidentTriage's
  `severity_t` is the only seeded enum colour set in the dashboard demo
  set, and it round-trips through `String.to_existing_atom/1` on the
  command-handler path (the enum atoms are loaded into the BEAM when this
  module compiles, so the conversion is safe).

  Seeded alongside ApprovalFlow under the same `:seed_flows` config gate by
  `ColouredFlowDashboard.Seed.run/1`.
  """

  use ColouredFlow.DSL

  name "Incident Triage Demo"
  version "1.0.0"

  colset alert_t() :: boolean()
  colset severity_t() :: :low | :medium | :high
  colset note_t() :: binary()
  colset triaged_t() :: {severity_t(), alert_t(), note_t()}

  var alert :: alert_t()
  var severity :: severity_t()
  var acknowledged :: alert_t()
  var note :: note_t()

  place :pending, :alert_t
  place :triaged, :triaged_t

  initial_marking :pending, ~MS[true]

  transition :triage do
    input :pending, bind({1, alert})
    output :triaged, {1, {severity, acknowledged, note}}
  end
end
