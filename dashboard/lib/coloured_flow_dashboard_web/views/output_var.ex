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
    * `:json`    — fallback for `:tuple`, `:map`, `:union`, `:list`, `:float`,
      or any unknown construct. The SPA renders a `Textarea` and treats the
      contents as raw JSON.

  `hint` carries a short reason whenever the resolver could not pick a
  richer kind — the SPA shows it as helper text under the field.
  """

  use Musubi.State

  state do
    field :name, String.t()
    field :colour_set, String.t()
    field :kind, :string | :integer | :boolean | :enum | :json
    field :enum_values, list(String.t()) | nil
    field :hint, String.t() | nil
  end
end
