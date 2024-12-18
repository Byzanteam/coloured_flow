defmodule ColouredFlow.Validators.Exceptions.InvalidGuardError do
  @moduledoc """
  This exception is raised when a guard is invalid:
  1. vars is not from variables bound to incoming-arcs, or constants
  """

  use TypedStructor

  @type reason() :: :unbound_vars

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
    The guard is invalid, due to #{inspect(exception.reason)}.
    #{exception.message}
    """
  end
end
