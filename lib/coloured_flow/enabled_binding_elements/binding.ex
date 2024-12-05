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
  @spec combine(bindings_list :: [[binding()]]) :: [binding()]
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
  Get the bindings from a place tokens(`t:ColouredFlow.MultiSet.t/0`) that match the arc expression expression (see detail at`t:ColouredFlow.Expression.Arc.binding/0`).
  """
  @spec match_bag(
          place_tokens_bag :: MultiSet.t(),
          arc_binding :: ArcExpression.binding(),
          value_var_context :: atom()
        ) :: [binding()]
  def match_bag(place_tokens_bag, arc_binding, value_var_context \\ nil) do
    place_tokens_bag
    |> MultiSet.to_pairs()
    |> Enum.flat_map(&match(&1, arc_binding, value_var_context))
  end

  @doc """
  Get the bindings from a token (`t:ColouredFlow.MultiSet.pair/0`) that match the arc_binding expression (see detail at`t:ColouredFlow.Expression.Arc.binding/0`).
  """
  @spec match(
          place_tokens :: MultiSet.pair(),
          arc_binding :: ArcExpression.binding(),
          value_var_context :: atom()
        ) :: [binding()]
  def match(place_tokens, arc_binding, value_var_context \\ nil)

  def match(place_tokens, {{:cpn_bind_literal, coefficient}, value_pattern}, value_var_context),
    do: literal_match(place_tokens, coefficient, value_pattern, value_var_context)

  def match(place_tokens, {{:cpn_bind_variable, coefficient}, value_pattern}, value_var_context),
    do: variable_match(place_tokens, coefficient, value_pattern, value_var_context)

  defp literal_match(place_tokens, expected_coefficient, value_pattern, value_var_context)

  defp literal_match(
         {token_coefficient, _token_value},
         expected_coefficient,
         _value_pattern,
         _binding_context
       )
       when expected_coefficient > token_coefficient,
       do: []

  defp literal_match(
         {token_coefficient, token_value},
         expected_coefficient,
         value_pattern,
         value_var_context
       ) do
    case match_value_pattern(token_value, value_pattern, value_var_context) do
      :error ->
        []

      {:ok, binding} ->
        prepend_coefficient_binding(token_coefficient, expected_coefficient, binding)
    end
  end

  defp variable_match(
         {token_coefficient, token_value},
         {coefficient_var, _meta},
         value_pattern,
         value_var_context
       ) do
    case match_value_pattern(token_value, value_pattern, value_var_context) do
      :error ->
        []

      {:ok, binding} ->
        case Keyword.fetch(binding, coefficient_var) do
          :error ->
            for coeff <- 0..token_coefficient do
              [{coefficient_var, coeff} | binding]
            end

          {:ok, coefficient} ->
            prepend_coefficient_binding(token_coefficient, coefficient, binding)
        end
    end
  end

  @spec match_value_pattern(
          MultiSet.value(),
          ArcExpression.value_pattern(),
          value_var_context :: atom()
        ) ::
          {:ok, [binding()]} | :error
  defp match_value_pattern(token_value, value_pattern, value_var_context) do
    ast =
      build_match_expr(
        value_pattern,
        Macro.escape(token_value),
        value_var_context
      )

    ast
    |> Code.eval_quoted()
    |> elem(0)
  rescue
    _error -> []
  end

  defp prepend_coefficient_binding(token_coefficient, expected_coefficient, binding) do
    if 0 === expected_coefficient do
      [binding]
    else
      result = div(token_coefficient, expected_coefficient)
      List.duplicate(binding, result)
    end
  end

  @spec build_match_expr(pattern :: Macro.t(), value :: Macro.t(), value_var_context :: atom()) ::
          Macro.t()
  def build_match_expr(pattern, value, value_var_context) do
    quote generated: true do
      case unquote(value) do
        unquote(pattern) -> {:ok, binding(unquote(value_var_context))}
        _ -> :error
      end
    end
  end
end
