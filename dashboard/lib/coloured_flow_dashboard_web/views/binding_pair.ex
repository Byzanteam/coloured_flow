defmodule ColouredFlowDashboardWeb.Views.BindingPair do
  @moduledoc """
  Wire-shape of one `{var_name, value}` entry of a binding element, rendered
  as a row in the operator outputs drawer's BINDING block.

  `name` is the variable's string-encoded atom (e.g. `"verdict"`); `value` is
  the pre-formatted `inspect/1` rendering of the runtime term (e.g. `"true"`,
  `~s("approve")`, `"{1, true}"`). Producing the value server-side keeps the
  SPA free of any Elixir term decoding for the binding read-out and lets
  values that themselves contain commas (tuples, strings) render in a single
  list row without the client needing to split on a delimiter.

  The structured pair list is the canonical wire shape; the legacy
  `binding_summary` string (`"name = value, ..."`) on
  `ColouredFlowDashboardWeb.Views.WorkitemRow` is kept for callers that still
  consume the flattened blob.
  """

  use Musubi.State

  state do
    field :name, String.t()
    field :value, String.t()
  end
end
