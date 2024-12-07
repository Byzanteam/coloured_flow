defmodule ColouredFlow.Definition.ColourSet.Value do
  @moduledoc """
  The value of a colour set.
  """

  @doc """
  Check if the value is valid.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec valid?(value :: term()) :: boolean()
  def valid?(term)

  def valid?(int) when is_integer(int), do: true
  def valid?(float) when is_float(float), do: true
  def valid?(bool) when is_boolean(bool), do: true
  def valid?(binary) when is_binary(binary), do: true
  def valid?({}), do: true

  # union: place it before tuple
  def valid?({tag, value}) when is_atom(tag) do
    valid?(value)
  end

  # tuple
  def valid?(tuple) when is_tuple(tuple) and tuple_size(tuple) >= 2 do
    values = Tuple.to_list(tuple)

    Enum.all?(values, &valid?/1)
  end

  # map
  def valid?(map) when is_map(map) and map_size(map) >= 1 do
    Enum.all?(map, fn
      {key, value} when is_atom(key) -> valid?(value)
      _other -> false
    end)
  end

  # enum
  def valid?(enum) when is_atom(enum), do: true

  # list
  def valid?(list) when is_list(list) do
    Enum.all?(list, &valid?/1)
  end

  def valid?(_value), do: false

  @type shape() ::
          :integer
          | :float
          | :boolean
          | :binary
          | :unit
          | {:union, %{atom() => shape()}}
          | {:tuple, [shape()]}
          | {:map, %{atom() => shape()}}
          | {:enum, [atom()]}
          # any list is empty_list
          | :any_list
          | {:list, shape()}

  @doc """
  Infer the shape of the value.

  ## Examples:

      iex> shape("foo")
      {:ok, :binary}

      iex> shape({"foo", 1, [1]})
      {:ok, {:tuple, [:binary, :integer, {:list, :integer}]}}

      iex> shape([%{name: "Alice", age: 20}, %{name: "Bob", age: 21}])
      {:ok, {:list, {:map, %{name: :binary, age: :integer}}}}

      iex> shape([])
      {:ok, :any_list}
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec shape(value :: term()) :: {:ok, shape()} | :error
  def shape(value)
  def shape(value) when is_integer(value), do: {:ok, :integer}
  def shape(value) when is_float(value), do: {:ok, :float}
  def shape(value) when is_boolean(value), do: {:ok, :boolean}
  def shape(value) when is_binary(value), do: {:ok, :binary}
  def shape({}), do: {:ok, :unit}

  # union
  def shape({tag, value}) when is_atom(tag) do
    with {:ok, shape} <- shape(value), do: {:ok, {:union, %{tag => shape}}}
  end

  # tuple
  def shape(tuple) when is_tuple(tuple) and tuple_size(tuple) >= 2 do
    values = Tuple.to_list(tuple)

    values
    |> Enum.reduce_while([], fn value, acc ->
      case shape(value) do
        {:ok, shape} -> {:cont, [shape | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      shapes -> {:ok, {:tuple, Enum.reverse(shapes)}}
    end
  end

  # map
  def shape(map) when is_map(map) and map_size(map) >= 1 do
    map
    |> Enum.reduce_while([], fn
      {key, value}, acc when is_atom(key) ->
        case shape(value) do
          {:ok, shape} -> {:cont, [{key, shape} | acc]}
          :error -> {:halt, :error}
        end

      {_key, _value}, _acc ->
        {:halt, :error}
    end)
    |> case do
      :error -> :error
      shapes -> {:ok, {:map, Map.new(shapes)}}
    end
  end

  # enum
  def shape(enum) when is_atom(enum), do: {:ok, {:enum, [enum]}}

  # list
  def shape([]), do: {:ok, :any_list}

  def shape(list) when is_list(list) do
    list
    |> Enum.reduce_while(nil, &list_shape_reducer/2)
    |> case do
      :error -> :error
      shape -> {:ok, {:list, shape}}
    end
  end

  def shape(_value), do: :error

  defp list_shape_reducer(value, prev_shape)

  defp list_shape_reducer(value, nil) do
    case shape(value) do
      {:ok, shape} -> {:cont, shape}
      :error -> {:halt, :error}
    end
  end

  defp list_shape_reducer(value, prev_shape) do
    case shape(value) do
      {:ok, ^prev_shape} ->
        {:cont, prev_shape}

      {:ok, shape} ->
        case list_shapes_compatibility(prev_shape, shape) do
          {:ok, shape} -> {:cont, shape}
          :error -> {:halt, :error}
        end

      :error ->
        {:halt, :error}
    end
  end

  defp list_shapes_compatibility({:union, shapes1}, {:union, shapes2}) do
    shapes1
    |> Map.merge(shapes2, fn _tag, shape1, shape2 ->
      case list_shapes_compatibility(shape1, shape2) do
        {:ok, shape} -> shape
        :error -> :error
      end
    end)
    |> Enum.reduce_while(%{}, fn {tag, shape}, acc ->
      case shape do
        :error -> {:halt, :error}
        _other -> {:cont, Map.put(acc, tag, shape)}
      end
    end)
    |> case do
      :error -> :error
      map -> {:ok, {:union, map}}
    end
  end

  defp list_shapes_compatibility({:enum, items1}, {:enum, items2}) do
    {:ok, {:enum, items1 |> Enum.concat(items2) |> Enum.uniq()}}
  end

  defp list_shapes_compatibility(:any_list, :any_list), do: {:ok, :any_list}
  defp list_shapes_compatibility(:any_list, {:list, shape}), do: {:ok, {:list, shape}}
  defp list_shapes_compatibility({:list, shape}, :any_list), do: {:ok, {:list, shape}}

  defp list_shapes_compatibility(shape, shape), do: {:ok, shape}
  defp list_shapes_compatibility(_shape1, _shape2), do: :error
end
