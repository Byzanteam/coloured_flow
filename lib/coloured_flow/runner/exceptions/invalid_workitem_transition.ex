defmodule ColouredFlow.Runner.Exceptions.InvalidWorkitemTransition do
  @moduledoc """
  This exception is raised when the workitem transition is invalid, such as the
  workitem is not enabled to be started, or completed.

  See workitem transition details in
  `ColouredFlow.Runner.Enactment.WorkitemTransition`.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Storage

  @typep transition() ::
           unquote(
             Workitem.__transitions__()
             |> Enum.map(&elem(&1, 1))
             |> Enum.uniq()
             |> ColouredFlow.Types.make_sum_type()
           )

  typed_structor definer: :defexception, enforce: true do
    field :id, Workitem.id()
    field :enactment_id, Storage.enactment_id()
    field :state, Workitem.state()
    field :transition, transition()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
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
