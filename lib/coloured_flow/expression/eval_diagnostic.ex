defmodule ColouredFlow.Expression.EvalDiagnostic do
  @moduledoc """
  A diagnostic message that is returned when an expression is evaluated.
  """

  use TypedStructor

  typed_structor definer: :defexception, enforce: true do
    field :message, String.t()
    field :position, Code.position()
    field :file, Path.t(), enforce: false
    field :stacktrace, Exception.stacktrace()
    field :source, Path.t(), enforce: false
    field :span, {line :: pos_integer(), column :: pos_integer()}, enforce: false
    field :severity, :error | :warning | :info
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end
end
