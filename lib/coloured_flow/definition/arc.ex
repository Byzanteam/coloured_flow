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
  @type binding() :: {
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

    field :bindings,
          list(binding()),
          default: [],
          doc: """
          The result that are returned by the arc, is form of a multi-set of tokens.

          - `[{1, {:cpn_bind_variable, :x}}]`: binds 1 token of colour `:x`
          - `[{2, {:cpn_bind_variable, :x}}, {3, {:cpn_bind_variable, :y}}]`: binds 2 tokens of colour `:x` or 3 tokens of colour `:y`
          - `[{:x, {:cpn_bind_variable, :y}}]`: binds `x` tokens of colour `:y`
          - `[{0, {:cpn_bind_variable, :x}}]`: binds 0 tokens (empty tokens) of colour `:x`
          """
  end

  @doc """
  Build bindings from the expression of the arc.

  ## Examples

      iex> expression = ColouredFlow.Definition.Expression.build!("bind {a, b}")
      iex> {:ok, binding} = build_bindings(expression)
      iex> [{{:cpn_bind_variable, :a}, {:cpn_bind_variable, :b}}] = binding
  """
  @spec build_bindings(Expression.t()) ::
          {:ok, list(binding())} | {:error, ColouredFlow.Expression.compile_error()}
  def build_bindings(%Expression{} = expression) do
    bindings = extract_bindings(expression.expr)
    check_binding_vars(expression.vars, bindings)
  end

  @spec build_bindings!(Expression.t()) :: list(binding())
  def build_bindings!(%Expression{} = expression) do
    case build_bindings(expression) do
      {:ok, bindings} -> bindings
      {:error, reason} -> raise inspect(reason)
    end
  end

  defp extract_bindings(quoted) do
    quoted
    |> Macro.prewalk([], fn
      {:bind, _meta, [binding]} = ast, acc ->
        {ast, [ArcExpression.extract_binding(binding) | acc]}

      ast, acc ->
        {ast, acc}
    end)
    |> elem(1)
  end

  defp check_binding_vars(vars, bindings) do
    binding_vars = Enum.flat_map(bindings, &ArcExpression.get_var_names/1)
    binding_vars = Map.new(binding_vars)
    diff = Map.drop(binding_vars, vars)

    case Map.to_list(diff) do
      [] ->
        {:ok, Enum.map(bindings, &ArcExpression.prune_meta/1)}

      [{name, meta} | _rest] ->
        {
          :error,
          {
            meta,
            "missing binding variable in vars: #{inspect(name)}",
            ""
          }
        }
    end
  end
end
