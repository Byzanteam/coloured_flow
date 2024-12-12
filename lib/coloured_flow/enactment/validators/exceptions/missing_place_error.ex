defmodule ColouredFlow.Enactment.Validators.Exceptions.MissingPlaceError do
  @moduledoc """
  This exception is raised when the place of the marking is not found in the cpnet.
  """

  use TypedStructor

  typed_structor definer: :defexception, enforce: true do
    field :place, String.t()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The place with name #{exception.place} not found in the coloured petri net.
    """
  end
end
