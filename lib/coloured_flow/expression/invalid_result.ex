defmodule ColouredFlow.Expression.InvalidResult do
  @moduledoc """
  An error occurs when the result of the expression is invalid, i.e., it does not
  return a boolean value for the termination criteria.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Expression

  typed_structor definer: :defexception, enforce: true do
    field :expression, Expression.t()

    field :message, String.t()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(exception) do
    """
    An invalid result was returned by the expression: #{exception.message}

    Code: #{exception.expression.code}
    """
  end
end
