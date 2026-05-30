defmodule ColouredFlowDashboardWeb.Views.NetDiagramPlace do
  @moduledoc """
  Wire-shape of a single place node rendered by the React Flow net diagram.

  `tokens_count` and `tokens_summary` mirror `MarkingRow` exactly — the store
  uses the markings stream as the source of truth so the diagram stays
  consistent with the Markings tab.
  """

  use Musubi.State

  state do
    field :name, String.t()
    field :colour_set, String.t()
    field :tokens_count, integer()
    field :tokens_summary, String.t()
  end
end
