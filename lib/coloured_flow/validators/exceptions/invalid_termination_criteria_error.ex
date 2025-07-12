defmodule ColouredFlow.Validators.Exceptions.InvalidTerminationCriteriaError do
  @moduledoc """
  The exception is raised when the termination criteria are invalid. See the
  definition of valid criteria in
  `ColouredFlow.Validators.Definition.TerminationCriteriaValidator`.
  """

  use TypedStructor

  @type reason() :: :unknown_vars

  typed_structor definer: :defexception, enforce: true do
    field :reason, reason()
    field :message, String.t()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The termination criteria are invalid, due to #{inspect(exception.reason)}.
    #{exception.message}
    """
  end
end
