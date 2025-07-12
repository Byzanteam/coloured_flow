defmodule ColouredFlow.Validators.Exceptions.InvalidArcError do
  @moduledoc """
  This exception is raised when an arc is invalid. See the definition of a valid
  arc in `ColouredFlow.Validators.Definition.ArcValidator`.
  """

  use TypedStructor

  @type reason() :: :incoming_unbound_vars | :outgoing_unbound_vars

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
    The Arc is invalid, due to #{inspect(exception.reason)}.
    #{exception.message}
    """
  end
end
