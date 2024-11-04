defmodule ColouredFlow.Runner do
  @moduledoc """
  The ColouredFlow runner.
  """

  alias ColouredFlow.Runner.Enactment.Supervisor, as: EnactmentSupervisor
  alias ColouredFlow.Runner.Enactment.WorkitemTransition

  defdelegate start_enactment(enactment_id), to: EnactmentSupervisor

  defdelegate allocate_workitem(enactment_id, workitem_id), to: WorkitemTransition
  defdelegate allocate_workitems(enactment_id, workitem_ids), to: WorkitemTransition

  defdelegate start_workitem(enactment_id, workitem_id), to: WorkitemTransition
  defdelegate start_workitems(enactment_id, workitem_ids), to: WorkitemTransition

  defdelegate complete_workitem(enactment_id, workitem_id_and_outputs), to: WorkitemTransition
  defdelegate complete_workitems(enactment_id, workitem_ids_and_outputs), to: WorkitemTransition
end
