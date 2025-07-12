defmodule ColouredFlow.Validators.Exceptions.InvalidActionError do
  @moduledoc """
  This exception is raised when an action is invalid. See the definition of a
  valid arc in `ColouredFlow.Validators.Definition.ActionValidator`.
  """

  use TypedStructor

  @type reason() :: :output_not_variable | :bound_output

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
    The Action is invalid, due to #{inspect(exception.reason)}.
    #{exception.message}
    """
  end
end
