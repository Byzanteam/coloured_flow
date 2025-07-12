defmodule ColouredFlow.EnabledBindingElements.Binding do
  @moduledoc """
  The utility functions for bindings.
  """

  alias ColouredFlow.MultiSet

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Variable
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Expression.Arc, as: ArcExpression

  @typep binding() :: BindingElement.binding()

  @doc """
  Get the conflicts between two bindings.

  ## Examples

      iex> get_conflicts([{:x, 1}, {:y, 2}], [{:x, 1}, {:y, 3}])
      [{:y, {2, 3}}]

      iex> get_conflicts([x: 0, y: 3], [y: 2])
      [y: {3, 2}]

      iex> get_conflicts([y: 2], [x: 0, y: 3])
      [y: {2, 3}]

      iex> get_conflicts([], [{:x, 1}, {:y, 2}])
      []

      iex> get_conflicts([{:x, 1}, {:y, 2}], [{:z, 3}])
      []
  """
  @spec get_conflicts(binding1 :: [binding()], binding2 :: [binding()]) ::
          [{Variable.name(), {ColourSet.value(), ColourSet.value()}}]
  def get_conflicts(binding1, []) when is_list(binding1), do: []
  def get_conflicts([], binding2) when is_list(binding2), do: []

  def get_conflicts(binding1, binding2) when is_list(binding1) and is_list(binding2) do
    binding1 = Map.new(binding1)
    binding2 = Map.new(binding2)

    conflicts =
      Map.intersect(binding1, binding2, fn _k, v1, v2 ->
        {v1, v2}
      end)

    Enum.filter(conflicts, fn {_key, {v1, v2}} -> v1 != v2 end)
  end

  @doc """
  Compute combinations of bindings that do not conflict.

  ## Examples

      iex> combine([[[x: 1, y: 2], [x: 1, y: 3]], [[x: 1], [x: 3]]])
      [[y: 2, x: 1], [y: 3, x: 1]]

      iex> combine([[[x: 1, y: 2], [x: 1, y: 3]], [[x: 1], [x: 3]], [[z: 1], [z: 2]]])
      [[y: 3, x: 1, z: 2], [y: 3, x: 1, z: 1], [y: 2, x: 1, z: 2], [y: 2, x: 1, z: 1]]

      iex> combine([[[x: 1, y: 2], [x: 1, y: 3]], [[x: 1], [x: 3]], [[y: 3]]])
      [[x: 1, y: 3]]

      iex> combine([[[x: 1, y: 2]], [[x: 1, y: 3]]])
      []

      iex> combine([[[x: 1, y: 2]]])
      [[x: 1, y: 2]]
  """
  @spec combine(bindings_list :: [[[binding()]]]) :: [[binding()]]
  def combine(bindings_list) do
    Enum.reduce(bindings_list, [[]], fn bindings, prevs ->
      for prev <- prevs, binding <- bindings, reduce: [] do
        acc ->
          case get_conflicts(prev, binding) do
            [] -> [Keyword.merge(prev, binding) | acc]
            _other -> acc
          end
      end
    end)
  end

  @doc """
  Get the bindings from a place tokens(`t:ColouredFlow.MultiSet.t/0`) that match
  the arc expression expression (see detail at
  `t:ColouredFlow.Expression.Arc.bind_expr/0`).
  """
  @spec match_bag(
          place_tokens_bag :: MultiSet.t(),
          arc_bind_expr :: ArcExpression.bind_expr(),
          value_var_context :: atom()
        ) :: [binding()]
  def match_bag(place_tokens_bag, arc_bind_expr, value_var_context \\ nil) do
    place_tokens_bag
    |> MultiSet.to_pairs()
    |> Enum.flat_map(&match(&1, arc_bind_expr, value_var_context))
  end

  @doc """
  Get the bindings from a token (`t:ColouredFlow.MultiSet.pair/0`) that match the
  arc_bind expression (see detail at `t:ColouredFlow.Expression.Arc.bind_expr/0`).
  """
  @spec match(
          place_tokens :: MultiSet.pair(),
          arc_bind_expr :: ArcExpression.bind_expr(),
          arc_bind_var_context :: atom()
        ) :: [binding()]
  def match(place_tokens, arc_bind_expr, arc_bind_var_context \\ nil) do
    coefficient =
      case arc_bind_expr do
        {coefficient, _value_pattern} -> coefficient
        {:when, _meta, [{coefficient, _value_pattern}, _guard]} -> coefficient
      end

    if Macro.quoted_literal?(coefficient) do
      if is_integer(coefficient) and coefficient >= 0 do
        literal_match(place_tokens, coefficient, arc_bind_expr, arc_bind_var_context)
      else
        # skip if coefficient is not a non-negative integer
        []
      end
    else
      variable_match(place_tokens, arc_bind_expr, arc_bind_var_context)
    end
  end

  defp literal_match(place_tokens, expected_coefficient, value_pattern, value_var_context)

  defp literal_match(
         {token_coefficient, _token_value},
         expected_coefficient,
         _bind,
         _bind_context
       )
       when expected_coefficient > token_coefficient,
       do: []

  defp literal_match(
         {token_coefficient, token_value},
         expected_coefficient,
         expr,
         bind_var_context
       ) do
    case match_bind_expr({expected_coefficient, token_value}, expr, bind_var_context) do
      :error ->
        []

      {:ok, expr, _place_tokens} ->
        duplicate_binding(token_coefficient, expected_coefficient, expr)
    end
  end

  defp variable_match(place_tokens, expr, bind_var_context)

  defp variable_match({token_coefficient, token_value}, expr, bind_var_context) do
    Enum.flat_map(0..token_coefficient, fn coefficient ->
      case match_bind_expr({coefficient, token_value}, expr, bind_var_context) do
        :error ->
          []

        {:ok, expr, {coefficient, _value}} ->
          duplicate_binding(token_coefficient, coefficient, expr)
      end
    end)
  end

  @spec match_bind_expr(MultiSet.pair(), ArcExpression.bind_expr(), bind_var_context :: atom()) ::
          {:ok, Code.binding(), MultiSet.pair()} | :error
  defp match_bind_expr(place_tokens, expr, bind_var_context) do
    value = Macro.escape(place_tokens)
    coefficient_var = Macro.var(:coefficient, __MODULE__)
    value_var = Macro.var(:value, __MODULE__)

    ast =
      quote generated: true do
        with(
          {unquote(coefficient_var), unquote(value_var)} <- unquote(value),
          unquote(expr) <- {unquote(coefficient_var), unquote(value_var)}
        ) do
          {
            :ok,
            binding(unquote(bind_var_context)),
            {unquote(coefficient_var), unquote(value_var)}
          }
        else
          _other -> :error
        end
      end

    ast
    |> Code.eval_quoted()
    |> elem(0)
  rescue
    _error -> :error
  end

  defp duplicate_binding(token_coefficient, expected_coefficient, binding) do
    if 0 === expected_coefficient do
      [binding]
    else
      result = div(token_coefficient, expected_coefficient)
      List.duplicate(binding, result)
    end
  end

  @spec build_match_expr(expr :: ArcExpression.bind_expr()) :: Macro.t()
  def build_match_expr(expr) do
    quote generated: true do
      case nil do
        unquote(expr) -> binding()
      end
    end
  end

  @spec apply_constants_to_bind_expr(
          arc_bind_expr :: ArcExpression.bind_expr(),
          constants :: %{ColourSet.name() => ColourSet.value()}
        ) :: ArcExpression.bind_expr()
  def apply_constants_to_bind_expr(arc_bind_expr, constants) do
    Macro.postwalk(arc_bind_expr, fn
      {var, meta, context} when is_atom(var) and is_atom(context) ->
        case Map.fetch(constants, var) do
          {:ok, value} -> Macro.escape(value)
          :error -> {var, meta, context}
        end

      other ->
        other
    end)
  end
end
