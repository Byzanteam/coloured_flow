defmodule ColouredFlow.EnabledBindingElements.Binding do
  @moduledoc """
  The utility functions for bindings.
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Variable

  @typep binding() :: [{Variable.name(), ColourSet.value()}]

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
  @spec get_conflicts(binding1 :: binding(), binding2 :: binding()) ::
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
end
