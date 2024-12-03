defmodule ColouredFlow.Definition.ColourSet.Of do
  @moduledoc """
  Functions to check the colour set.
  """

  alias ColouredFlow.Definition.ColourSet

  @type context() :: %{fetch_type: (type_name :: atom() -> {:ok, ColourSet.descr()} | :error)}

  @doc """
  Check if the value is of the type.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec of_type(value :: term(), descr :: ColourSet.descr(), context()) ::
          {:ok, ColourSet.value()} | :error
  def of_type(value, descr, context) do
    if type?(value, descr, context) do
      {:ok, value}
    else
      :error
    end
  end

  # primitive
  defp type?(int, {:integer, []}, _context) when is_integer(int), do: true
  defp type?(float, {:float, []}, _context) when is_float(float), do: true
  defp type?(bool, {:boolean, []}, _context) when is_boolean(bool), do: true
  defp type?(binary, {:binary, []}, _context) when is_binary(binary), do: true
  defp type?({}, {:unit, []}, _context), do: true

  # composite
  defp type?(tuple, {:tuple, types}, context)
       when is_tuple(tuple) and tuple_size(tuple) === length(types) do
    values = Tuple.to_list(tuple)

    Enum.all?(Enum.zip(values, types), &type?(elem(&1, 0), elem(&1, 1), context))
  end

  defp type?(map, {:map, types}, context)
       when is_map(map) and map_size(map) === map_size(types) do
    Enum.all?(map, fn {key, value} ->
      case Map.fetch(types, key) do
        :error -> false
        {:ok, type} -> type?(value, type, context)
      end
    end)
  end

  defp type?(enum, {:enum, items}, _context) when is_atom(enum) do
    enum in items
  end

  defp type?({tag, value}, {:union, types}, context) when is_atom(tag) do
    case Map.fetch(types, tag) do
      :error -> false
      {:ok, type} -> type?(value, type, context)
    end
  end

  defp type?(list, {:list, type}, context) when is_list(list) do
    Enum.all?(list, &type?(&1, type, context))
  end

  # compound types
  defp type?(value, {name, []}, context)
       when name not in unquote(ColourSet.Descr.__built_in_types__()) do
    case context.fetch_type.(name) do
      :error -> false
      {:ok, descr} -> type?(value, descr, context)
    end
  end

  defp type?(_value, _type, _context), do: false
end
