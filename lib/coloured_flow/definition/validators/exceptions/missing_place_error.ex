defmodule ColouredFlow.Definition.Validators.Exceptions.MissingPlaceError do
  @moduledoc """
  This exception is raised when a place is missing,
  e.g., one of the markings is not found in the cpnet.
  """

  use TypedStructor

  typed_structor definer: :defexception, enforce: true do
    field :place, String.t()
    field :message, String.t()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The place with name #{exception.place} not found in the coloured petri net.
    #{exception.message}
    """
  end
end
