defmodule ColouredFlow.Definition.Arc do
  @moduledoc """
  An arc is a directed connection between a transition and a place.
  """

  use TypedStructor

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable
  alias ColouredFlow.Expression.Arc, as: ArcExpression

  @type name() :: binary()
  @type orientation() :: :p_to_t | :t_to_p
  @type returning() :: {
          non_neg_integer() | {:cpn_bind_variable, Variable.name()},
          {:cpn_bind_variable, Variable.name()} | ColourSet.value()
        }

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :name, name()

    field :orientation, orientation(),
      doc: """
      The orientation of the arc, whether it is from a transition to a place,
      or from a place to a transition.

      - `:p_to_t`: from a place to a transition
      - `:t_to_p`: from a transition to a place
      """

    field :transition, Transition.name()
    field :place, Place.name()

    field :expression, Expression.t(),
      doc: """
      The expression that is used to evaluate the arc.

      When a transition is fired, the tokens in the in-coming places are matched
      with the in-coming arcs will be consumed, and the tokens in the out-going places
      are updated with the out-going arcs.

      Note that incoming arcs cannot refer to an unbound variable,
      but they can refer to variables bound by other incoming arcs
      (see <https://cpntools.org/2018/01/09/resource-allocation-example/>).
      However, outgoing arcs are allowed to refer to an unbound variable
      that will be updated during the transition action.
      """

    field :returnings,
          list(returning()),
          default: [],
          doc: """
          The result that are returned by the arc, is form of a multi-set of tokens.

          - `[{1, {:cpn_bind_variable, :x}}]`: return 1 token of colour `:x`
          - `[{2, {:cpn_bind_variable, :x}}, {3, {:cpn_bind_variable, :y}}]`: return 2 tokens of colour `:x` or 3 tokens of colour `:y`
          - `[{:x, {:cpn_bind_variable, :y}}]`: return `x` tokens of colour `:y`
          - `[{0, {:cpn_bind_variable, :x}}]`: return 0 tokens (empty tokens) of colour `:x`
          """
  end

  @doc """
  Build returnings from the expression of the arc.

  ## Examples

      iex> expression = ColouredFlow.Definition.Expression.build!("return {a, b}")
      iex> {:ok, returning} = build_returnings(expression)
      iex> [{{:cpn_bind_variable, :a}, {:cpn_bind_variable, :b}}] = returning
  """
  @spec build_returnings(Expression.t()) ::
          {:ok, list(returning())} | {:error, ColouredFlow.Expression.compile_error()}
  def build_returnings(expression) do
    returnings = extract_returnings(expression.expr)
    check_returning_vars(expression.vars, returnings)
  end

  @spec build_returnings!(Expression.t()) :: list(returning())
  def build_returnings!(expression) do
    case build_returnings(expression) do
      {:ok, returnings} -> returnings
      {:error, reason} -> raise reason
    end
  end

  defp extract_returnings(quoted) do
    quoted
    |> Macro.prewalk([], fn
      {:return, _meta, [returning]} = ast, acc ->
        {ast, [ArcExpression.extract_returning(returning) | acc]}

      ast, acc ->
        {ast, acc}
    end)
    |> elem(1)
  end

  defp check_returning_vars(vars, returnings) do
    returning_vars = Enum.flat_map(returnings, &ArcExpression.get_var_names/1)
    returning_vars = Map.new(returning_vars)
    diff = Map.drop(returning_vars, vars)

    case Map.to_list(diff) do
      [] ->
        {:ok, Enum.map(returnings, &ArcExpression.prune_meta/1)}

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
end
