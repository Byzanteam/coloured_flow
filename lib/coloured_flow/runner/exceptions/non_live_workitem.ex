defmodule ColouredFlow.Runner.Exceptions.NonLiveWorkitem do
  @moduledoc """
  The exception raised when the workitem is not live, such as the workitem is
  completed or withdrawn, or not even enabled at all.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :id, Workitem.id()
    field :enactment_id, Storage.enactment_id()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The workitem with ID #{exception.id} in the enactment with
    ID #{exception.enactment_id} is not live.

    The following are the possible reasons:
    1. The workitem is in `completed` state (one of #{Enum.join(Workitem.__completed_states__(), ", ")})
    2. The workitem is not enabled yet
    """
  end
end
