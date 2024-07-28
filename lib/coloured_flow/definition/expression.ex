defmodule ColouredFlow.Definition.Expression do
  @moduledoc """
  An expression is a quoted Elixir expression that can be evaluated
  """

  alias ColouredFlow.Definition.Variable

  use TypedStructor

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :expr, Macro.t(),
      default: nil,
      doc: "a quoted expression, `nil` is a valid expression that does nothing."

    field :vars, [Variable.name()],
      default: [],
      doc: """
      a list of variables that are used in the expression,
      when the expression is evaluated, the variables will
      be bound to the values that are passed in.
      """
  end

  @spec build(binary() | nil) ::
          {:ok, t()}
          | {:error, ColouredFlow.Expression.string_to_quoted_error()}
  def build(expr) when is_nil(expr) when expr === "", do: {:ok, %__MODULE__{}}

  def build(expr) when is_binary(expr) do
    case ColouredFlow.Expression.string_to_quoted(expr, __ENV__) do
      {:ok, quoted, vars} ->
        {:ok, %__MODULE__{expr: quoted, vars: Map.keys(vars)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec build!(binary() | nil) :: t()
  def build!(expr) do
    case build(expr) do
      {:ok, expr} -> expr
      {:error, reason} -> raise reason
    end
  end
end
