defmodule ColouredFlow.Definition.Arc do
  @moduledoc """
  An arc is a directed connection between a transition and a place.

  > #### TIP {: .tip}
  >
  > Note that the terms `incoming` and `outgoing` are relevant to the transition.
  > If the arc is linked from a place such that the orientation is `:p_to_t`, it
  > is considered an incoming arc; otherwise, it is considered an outgoing arc.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Expression.Arc, as: ArcExpression

  @type label() :: binary()
  @type orientation() :: :p_to_t | :t_to_p

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
      ```

      ```elixir
      # use `bind` with guard to bind the variable
      bind {1, x} when x > 2
      ```
      """
  end

  @doc """
  Build the expression for the arc.

  ## Examples

      iex> {:ok, %ColouredFlow.Definition.Expression{}} = build_expression(:p_to_t, "bind {a, b}")

      iex> {:error, {[], "missing `bind` in expression", "{a, b}"}} = build_expression(:p_to_t, "{a, b}")

      iex> {:ok, %ColouredFlow.Definition.Expression{}} = build_expression(:t_to_p, "{a, b}")
  """
  @spec build_expression(orientation(), code :: binary() | nil) ::
          {:ok, Expression.t()} | {:error, ColouredFlow.Expression.compile_error()}
  def build_expression(orientation, code)

  def build_expression(:p_to_t, code) do
    with {:ok, expression} <- Expression.build(code) do
      case validate_bind_exprs(expression.expr) do
        [] ->
          {:error, {[], "missing `bind` in expression", code}}

        validations ->
          case Enum.find(validations, &match?({:error, _reason}, &1)) do
            nil -> {:ok, expression}
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  def build_expression(:t_to_p, code) do
    Expression.build(code)
  end

  @spec build_expression!(orientation(), code :: binary() | nil) :: Expression.t()
  def build_expression!(orientation, code) do
    case build_expression(orientation, code) do
      {:ok, expression} -> expression
      {:error, reason} -> raise inspect(reason)
    end
  end

  defp validate_bind_exprs(quoted) do
    quoted
    |> Macro.prewalk([], fn
      {:bind, meta, [bind_expr]} = ast, acc ->
        validation =
          case ArcExpression.validate_bind_expr(bind_expr) do
            {:error, reason} -> {:error, {meta, reason, Macro.to_string(ast)}}
            :ok -> :ok
          end

        {ast, [validation | acc]}

      ast, acc ->
        {ast, acc}
    end)
    |> elem(1)
  end
end
