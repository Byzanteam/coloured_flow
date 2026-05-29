defmodule ColouredFlowDashboardWeb.Views.MarkingRow do
  @moduledoc """
  Wire-shape of a single place marking row rendered in the enactment detail
  Markings tab.

  Constructed at mount-time from
  `ColouredFlow.Runner.Enactment.Snapshot.markings` (potentially recovered by
  `ColouredFlow.Runner.Enactment.CatchingUp.apply/2` if newer occurrences
  exist) or from a live `:sys.get_state/1` peek when the enactment GenServer
  is up. The fields are intentionally pre-rendered strings so the SPA never
  has to know about `ColouredFlow.MultiSet` or `ColouredFlow.Definition.ColourSet`.
  """

  use Musubi.State

  state do
    field :place, String.t()
    field :colour_set, String.t()
    field :tokens_count, integer()
    field :tokens_summary, String.t()
  end
end
