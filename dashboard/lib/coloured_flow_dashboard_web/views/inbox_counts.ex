defmodule ColouredFlowDashboardWeb.Views.InboxCounts do
  @moduledoc """
  Header rollup rendered above the inbox table — running totals derived from
  the in-memory `ColouredFlowDashboardWeb.Views.WorkitemRow` set so the SPA
  never has to walk the stream client-side to compute its own badges.
  """

  use Musubi.State

  # Musubi's `state do` AST validator accepts `integer()`/`boolean()`/`atom()`,
  # string-key literal maps, and module references (`Mod.t()`); parameterised
  # map shapes (`%{K => V}`) and bare `non_neg_integer()` are out of scope.
  # `by_enactment` is keyed by an opaque enactment-id string, so a bare
  # `map()` is the narrowest valid type the DSL accepts. The values are
  # always non-negative integers by construction — see `InboxStore.compute_counts/2`.
  state do
    field :enabled, integer()
    field :started, integer()
    field :by_enactment, map()
  end
end
