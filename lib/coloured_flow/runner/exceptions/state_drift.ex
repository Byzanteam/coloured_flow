defmodule ColouredFlow.Runner.Exceptions.StateDrift do
  @moduledoc """
  The runner detected divergence between its in-memory state and what the storage
  layer believed: a Multi rolled back, or the number of rows updated did not match
  the number of workitems we expected to transition.

  Recovery is unsafe in-process: the workitem cache is stale. The runner records
  the event, marks `enactments.state = :exception`, and exits with
  `{:shutdown, {:fatal, :state_drift}}`. Operators can clear it via reoffer.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
    field :action, Workitem.transition_action()
    field :context, Storage.state_drift_context(), default: []
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    "State drift detected while handling action #{inspect(exception.action)} " <>
      "in enactment #{inspect(exception.enactment_id)}: " <>
      "the storage rejected the transition because the in-memory workitem cache " <>
      "is out of sync with the database. " <>
      "Context: #{inspect(exception.context)}."
  end
end
