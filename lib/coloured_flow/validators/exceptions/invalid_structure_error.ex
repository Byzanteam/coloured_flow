defmodule ColouredFlow.Validators.Exceptions.InvalidStructureError do
  @moduledoc """
  This exception is raised when the structure of the Coloured Petri Net is
  invalid.

  See `ColouredFlow.Validators.Definition.StructureValidator` for the definition
  of a well-structured Coloured Petri Net.
  """

  use TypedStructor

  @type reason() ::
          :empty_nodes
          | :missing_nodes
          | :dangling_nodes
          | :duplicate_arcs

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
    The structure of the Coloured Petri Net is invalid, due to #{inspect(exception.reason)}

    #{exception.message}
    """
  end
end
