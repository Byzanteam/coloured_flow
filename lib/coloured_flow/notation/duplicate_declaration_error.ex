defmodule ColouredFlow.Notation.DuplicateDeclarationError do
  @moduledoc """
  An error that occurs when a duplicate declaration is found.
  """

  use TypedStructor

  typed_structor definer: :defexception, enforce: true do
    field :name, String.t()
    field :type, :colset | :val | :var
    field :declaration, String.t()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    Duplicate declaration of #{exception.type}: `#{exception.name}`, in the declaration:

    #{exception.declaration}
    """
  end
end
