defmodule ColouredFlowDashboardWeb.Views.OutputVar do
  @moduledoc """
  Wire-shape of one free-variable slot the operator must fill when completing
  a workitem. Drives the M5 structured outputs drawer.

  Built at row construction time by
  `ColouredFlowDashboard.OutputSchemaBuilder.build/2` from the transition's
  output-arc inscriptions: every free variable listed in
  `Action.outputs` is paired with its declared colour set, and the colour set's
  descriptor is mapped to a renderable `kind`:

    * `:string`  — `binary()` → Kumo `Input` (text).
    * `:integer` — `integer()` → Kumo `Input` (number).
    * `:boolean` — `boolean()` → Kumo `Checkbox`.
    * `:enum`    — `:a | :b | :c` → Kumo `Select` populated from
      `enum_values` (atoms surface as strings; the runner re-atomises via
      `String.to_existing_atom/1`).
    * `:elixir`  — fallback for `:tuple`, `:map`, `:union`, `:list`, `:float`,
      or any unknown construct. The SPA renders a Kumo `InputArea` and
      expects the operator to type an Elixir term literal (e.g.
      `{:approve, "note"}`, `[user: "hi"]`, `:running`). The backend parses
      it with `Code.string_to_quoted/2` plus a literal-only walker.

  `hint` carries a short reason whenever the resolver could not pick a
  richer kind — the SPA shows it as helper text under the field. `example`
  carries a short literal preview suitable for the textarea placeholder when
  `kind` is `:elixir`.
  """

  use Musubi.State

  state do
    field :name, String.t()
    field :colour_set, String.t()
    field :kind, :string | :integer | :boolean | :enum | :elixir
    field :enum_values, list(String.t()) | nil
    field :hint, String.t() | nil
    field :example, String.t() | nil
  end
end
