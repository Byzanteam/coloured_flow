defmodule ColouredFlow.Definition.ColourSet.Of do
  @moduledoc """
  Functions to check the colour set.
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColourSet.Descr

  @type context() :: %{fetch_type: (type_name :: atom() -> {:ok, ColourSet.descr()} | :error)}

  @doc """
  Check if the value is of the type.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec of_type(value :: term(), descr :: ColourSet.descr(), context()) ::
          {:ok, ColourSet.value()} | :error
  def of_type(value, descr, context) do
    if type?(descr, value, context) do
      {:ok, value}
    else
      :error
    end
  end

  defp type?(descr, value, context) do
    do_type?(Descr.match(descr), descr, value, context)
  end

  defp do_type?({:built_in, :integer}, _descr, value, _context) when is_integer(value), do: true
  defp do_type?({:built_in, :float}, _descr, value, _context) when is_float(value), do: true
  defp do_type?({:built_in, :boolean}, _descr, value, _context) when is_boolean(value), do: true
  defp do_type?({:built_in, :binary}, _descr, value, _context) when is_binary(value), do: true
  defp do_type?({:built_in, :unit}, _descr, {}, _context), do: true

  defp do_type?({:built_in, :tuple}, {:tuple, types}, tuple, context)
       when is_tuple(tuple) and length(types) === tuple_size(tuple) do
    values = Tuple.to_list(tuple)

    types
    |> Stream.zip(values)
    |> Enum.all?(fn {descr, value} ->
      type?(descr, value, context)
    end)
  end

  defp do_type?({:built_in, :map}, {:map, types}, map, context)
       when is_map(map) and map_size(types) === map_size(map) do
    Enum.all?(types, fn {key, descr} ->
      case Map.fetch(map, key) do
        :error -> false
        {:ok, value} -> type?(descr, value, context)
      end
    end)
  end

  defp do_type?({:built_in, :enum}, {:enum, items}, enum, _context) when is_atom(enum),
    do: enum in items

  defp do_type?({:built_in, :union}, {:union, types}, {tag, value}, context)
       when is_atom(tag) do
    case Map.fetch(types, tag) do
      :error -> false
      {:ok, type} -> type?(type, value, context)
    end
  end

  defp do_type?({:built_in, :list}, {:list, type}, list, context) when is_list(list) do
    Enum.all?(list, &type?(type, &1, context))
  end

  defp do_type?({:built_in, _name}, _descr, _value, _context), do: false

  defp do_type?({:compound, name}, _descr, value, context) do
    case context.fetch_type.(name) do
      :error -> false
      {:ok, descr} -> type?(descr, value, context)
    end
  end

  defp do_type?(:unknown, _descr, _value, _context), do: false
end
