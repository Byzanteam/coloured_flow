defmodule ColouredFlow.Definition.Expression do
  @moduledoc """
  An expression is a quoted Elixir expression that can be evaluated
  """

  alias ColouredFlow.Definition.Variable

  use TypedStructor

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :code, binary() | nil,
      default: nil,
      doc: """
      the original code of the expression. `nil` is a valid code that does nothing.
      We store the code along with the `expr`, because compiling to `expr` will lose the original formatting.
      """

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

  @doc """
  Build an expression from code.

  Note that, `""` and `nil` are valid codes that are always evaluated to `nil`,
  and are treated as `false` in the guard of a transition.
  """
  @spec build(binary() | nil, Macro.Env.t()) ::
          {:ok, t()} | {:error, ColouredFlow.Expression.compile_error()}
  def build(expr, env \\ __ENV__)
  def build(expr, _env) when is_nil(expr) when expr === "", do: {:ok, %__MODULE__{}}

  def build(expr, env) when is_binary(expr) do
    with({:ok, quoted, vars} <- ColouredFlow.Expression.compile(expr, env)) do
      {:ok, %__MODULE__{code: expr, expr: quoted, vars: vars |> Map.keys() |> Enum.sort()}}
    end
  end

  @doc """
  Build an expression from code, raise if failed. See `build/1`.
  """
  @spec build!(binary() | nil, Macro.Env.t()) :: t()
  def build!(expr, env \\ __ENV__) do
    case build(expr, env) do
      {:ok, expr} -> expr
      {:error, reason} -> raise "failed to build expression: #{inspect(reason)}"
    end
  end
end
