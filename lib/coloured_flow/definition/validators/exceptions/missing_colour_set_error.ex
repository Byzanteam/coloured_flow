defmodule ColouredFlow.Definition.Validators.Exceptions.MissingColourSetError do
  @moduledoc """
  This exception is raised when the colour set is missing,
  but it is referred to by variables, constants, etc.
  """

  use TypedStructor

  typed_structor definer: :defexception, enforce: true do
    field :colour_set, ColouredFlow.Definition.ColourSet.name()
    field :message, String.t()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The colour set with name #{inspect(exception.colour_set)} is missing.
    #{exception.message}
    """
  end
end
