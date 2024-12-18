defmodule ColouredFlow.Validators.Exceptions.InvalidMarkingError do
  @moduledoc """
  This exception is raised when a marking is invalid:
  1. The place of a marking is not found in the cpnet.
  2. The tokens of a marking are invalid, e.g., color set mismatch.
  """

  use TypedStructor

  @type reason() :: :missing_place | :invalid_tokens

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
    The marking is invalid, due to #{inspect(exception.reason)}.
    #{exception.message}
    """
  end
end
