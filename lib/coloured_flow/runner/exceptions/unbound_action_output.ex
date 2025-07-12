defmodule ColouredFlow.Runner.Exceptions.UnboundActionOutput do
  @moduledoc """
  This exception is raised when the output is not found in outputs of the
  transition action, which usually occurs on the workitem completion when the
  outputs of the transition action are not bound.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable

  typed_structor definer: :defexception, enforce: true do
    field :transition, Transition.name()
    field :output, Variable.name()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The output variable `#{exception.output}` of the transition `#{exception.transition}`
    is not bound in the outputs of the transition action.
    """
  end
end
