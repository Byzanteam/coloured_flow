defmodule ColouredFlow.Definition.Expression do
  @moduledoc """
  An expression is a quoted Elixir expression that can be evaluated
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Variable

  use TypedStructor

  @type returning() :: {
          non_neg_integer() | {:cpn_returning_variable, Variable.name()},
          {:cpn_returning_variable, Variable.name()} | ColourSet.value()
        }

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

    field :returnings,
          list(returning()),
          default: [],
          doc: """
          The result that are returned by the arc, is form of a multi-set of tokens.

          - `[{1, {:cpn_returning_variable, :x}}]`: return 1 token of colour `:x`
          - `[{2, {:cpn_returning_variable, :x}}, {3, {:cpn_returning_variable, :y}}]`: return 2 tokens of colour `:x` or 3 tokens of colour `:y`
          - `[{:x, {:cpn_returning_variable, :y}}]`: return `x` tokens of colour `:y`
          - `[{0, {:cpn_returning_variable, :x}}]`: return 0 tokens (empty tokens) of colour `:x`
          """
  end

  @spec build(binary() | nil) ::
          {:ok, t()}
          | {:error, ColouredFlow.Expression.compile_error()}
  def build(expr) when is_nil(expr) when expr === "", do: {:ok, %__MODULE__{}}

  def build(expr) when is_binary(expr) do
    with(
      {:ok, quoted, vars, returnings} <- ColouredFlow.Expression.compile(expr, __ENV__),
      {:ok, returnings} <- check_returning_vars(vars, returnings)
    ) do
      {:ok, %__MODULE__{expr: quoted, vars: Map.keys(vars), returnings: returnings}}
    end
  end

  defp check_returning_vars(vars, returnings) do
    returning_vars = Enum.flat_map(returnings, &ColouredFlow.Expression.Returning.get_var_names/1)
    returning_vars = Map.new(returning_vars)
    vars = Enum.map(vars, &elem(&1, 0))
    diff = Map.drop(returning_vars, vars)

    case Map.to_list(diff) do
      [] ->
        {:ok, Enum.map(returnings, &ColouredFlow.Expression.Returning.prune_meta/1)}

      [{name, meta} | _rest] ->
        {
          :error,
          {
            meta,
            "missing returning variable in vars: #{inspect(name)}",
            ""
          }
        }
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
