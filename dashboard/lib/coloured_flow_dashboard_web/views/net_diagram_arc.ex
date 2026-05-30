defmodule ColouredFlowDashboardWeb.Views.NetDiagramArc do
  @moduledoc """
  Wire-shape of a single arc edge rendered by the React Flow net diagram.

  `orientation` is `:p_to_t` for an incoming arc (place → transition) and
  `:t_to_p` for an outgoing arc (transition → place). Musubi serialises the
  atom across the wire as its string form (`"p_to_t"` / `"t_to_p"`).
  """

  use Musubi.State

  state do
    field :place, String.t()
    field :transition, String.t()
    field :orientation, :p_to_t | :t_to_p
  end
end
