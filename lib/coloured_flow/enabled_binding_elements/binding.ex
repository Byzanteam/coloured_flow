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
end
