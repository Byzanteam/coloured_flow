defmodule ColouredFlow.Expression.EvalDiagnostic do
  @moduledoc """
  A diagnostic message that is returned when an expression is evaluated.
  """

  defexception [:message, :position, :file, :stacktrace, :source, :span, :severity]

  @impl Exception
  def exception(opts) do
    struct(__MODULE__, opts)
  end
end
