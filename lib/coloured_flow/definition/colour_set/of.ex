defmodule ColouredFlow.Definition.ColourSet.Of do
  @moduledoc """
  Functions to check the colour set.
  """

  alias ColouredFlow.Definition.ColourSet

  @doc """
  Check if the value is of the type.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec of_type(value :: term(), descr :: ColourSet.descr()) :: {:ok, ColourSet.value()} | :error
  def of_type(value, descr) do
    if type?(value, descr) do
      {:ok, value}
    else
      :error
    end
  end

  # primitive
  defp type?(int, {:integer, []}) when is_integer(int), do: true
  defp type?(float, {:float, []}) when is_float(float), do: true
  defp type?(bool, {:boolean, []}) when is_boolean(bool), do: true
  defp type?(binary, {:binary, []}) when is_binary(binary), do: true
  defp type?({}, {:unit, []}), do: true

  # composite
  defp type?(tuple, {:tuple, types})
       when is_tuple(tuple) and tuple_size(tuple) === length(types) do
    values = Tuple.to_list(tuple)

    Enum.all?(Enum.zip(values, types), &type?(elem(&1, 0), elem(&1, 1)))
  end

  defp type?(map, {:map, types}) when is_map(map) and map_size(map) === map_size(types) do
    Enum.all?(map, fn {key, value} ->
      case Map.fetch(types, key) do
        :error -> false
        {:ok, type} -> type?(value, type)
      end
    end)
  end

  defp type?(enum, {:enum, items}) when is_atom(enum) do
    enum in items
  end

  defp type?({tag, value}, {:union, types}) when is_atom(tag) do
    case Map.fetch(types, tag) do
      :error -> false
      {:ok, type} -> type?(value, type)
    end
  end

  defp type?(list, {:list, type}) when is_list(list) do
    Enum.all?(list, &type?(&1, type))
  end

  defp type?(_value, _type), do: false
end
