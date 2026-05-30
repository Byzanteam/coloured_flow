defmodule ColouredFlowDashboardWeb.Views.ColourSetDef do
  @moduledoc """
  Wire-shape of a single colour-set declaration surfaced to the operator UI.

  Operators looking at an enactment or flow can see place names and the colset
  *name* via `NetDiagramPlace.colour_set`, but not the colset *definition*
  (e.g. `outcome :: {verdict_t(), note_t()}`). This view exposes one row per
  cpnet colour set so the SPA can render a panel that explains the shape of
  each token type.

  `type_summary` is the Elixir-source-shaped rendering of the colour set's
  `descr` (see `ColouredFlow.Definition.ColourSet.descr/0`). Examples:

    * `colset trigger_t() :: boolean()` → `"boolean()"`
    * `colset outcome() :: {verdict_t(), note_t()}` →
      `"{verdict_t(), note_t()}"`
    * `colset severity_t() :: :low | :medium | :high` →
      `":low | :medium | :high"`
  """

  use Musubi.State

  state do
    field :name, String.t()
    field :type_summary, String.t()
    field :description, String.t() | nil
  end
end
