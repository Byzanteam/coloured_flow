defmodule ColouredFlow.Runner do
  @moduledoc """
  The ColouredFlow runner.
  """

  alias ColouredFlow.Runner.Enactment.WorkitemTransition

  defdelegate allocate_workitem(enactment_id, workitem_id), to: WorkitemTransition
  defdelegate allocate_workitems(enactment_id, workitem_ids), to: WorkitemTransition
end
