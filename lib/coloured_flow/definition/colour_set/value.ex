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
end
