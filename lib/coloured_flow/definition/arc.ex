defmodule ColouredFlow.Definition.Arc do
  @moduledoc """
  An arc is a directed connection between a transition and a place.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Expression.Arc, as: ArcExpression

  @type label() :: binary()
  @type orientation() :: :p_to_t | :t_to_p
  @typep binding() :: ArcExpression.binding()

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :label, label(),
      enforce: false,
      doc: "The label of the arc, optional, used for debugging."

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
      that will be updated during the transition action; that is,
      it will be bound by the action outputs.

      Examples:

      ```elixir
      if x > 0 do
        # use `bind` keyword to bind the variable
        bind {1, x}
      else
        bind {2, 1}
      end

      # the bindings are:
      # [{{:cpn_bind_literal, 2}, 1}, {{:cpn_bind_literal, 1}, {:x, [], nil}}]
      ```
      """

    field :bindings,
          list(binding()),
          default: [],
          doc: """
          The result that are returned by the arc, is form of a multi-set of tokens.

          - `[{{:cpn_bind_literal, 1}, {:x, [], nil}}]`: binds 1 token of colour `:x`
          - `[{{:cpn_bind_literal, 2}, {:x, [], nil}}, {3, {:cpn_bind_variable, :y}}]`: binds 2 tokens of colour `:x` or 3 tokens of colour `:y`
          - `[{{:cpn_bind_variable, :x}, {:y, [], nil}}]`: binds `x` tokens of colour `:y`
          - `[{{:cpn_bind_literal, 0}, {:x, [], nil}}]`: binds 0 tokens (empty tokens) of colour `:x`
          """
  end

  @doc """
  Build bindings from the expression of the in-coming arc.

  ## Examples

      iex> expression = ColouredFlow.Definition.Expression.build!("bind {a, b}")
      iex> {:ok, binding} = build_bindings(expression)
      iex> [{{:cpn_bind_variable, {:a, [line: 1, column: 7]}}, {:b, [line: 1, column: 10], nil}}] = binding
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
        {:ok, bindings}

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
