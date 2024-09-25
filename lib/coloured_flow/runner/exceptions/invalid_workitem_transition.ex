defmodule ColouredFlow.Runner.Exceptions.InvalidWorkitemTransition do
  @moduledoc """
  This exception is raised when the workitem transition is invalid, such as
  the workitem is not enabled to be allocated, started, or completed.

  See workitem transition details in `ColouredFlow.Runner.Enactment.WorkitemTransition`.
  """

  defexception [:id, :enactment_id, :state, :transition]

  @impl Exception
  def exception(arguments) when is_list(arguments) do
    %__MODULE__{
      id: Keyword.fetch!(arguments, :id),
      enactment_id: Keyword.fetch!(arguments, :enactment_id),
      state: Keyword.fetch!(arguments, :state),
      transition: Keyword.fetch!(arguments, :transition)
    }
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The workitem with ID #{exception.id} in the enactment with
    ID #{exception.enactment_id} is in `#{exception.state}` state,
    which is not allowed to transition via `#{exception.transition}`.

    See the workitem state machine in `ColouredFlow.Runner.Enactment.Workitem`.
    """
  end
end
