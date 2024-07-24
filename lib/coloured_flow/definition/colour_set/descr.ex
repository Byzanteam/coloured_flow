defmodule ColouredFlow.Definition.ColourSet.Descr do
  @moduledoc """
  The `descr` is used to describe the colour set.
  """

  @type t() :: ColouredFlow.Definition.ColourSet.descr()

  @spec valid?(descr :: t()) :: boolean()
  def valid?(descr)

  # primitive
  def valid?({:integer, []}), do: true
  def valid?({:float, []}), do: true
  def valid?({:boolean, []}), do: true
  def valid?({:binary, []}), do: true
  def valid?({:unit, []}), do: true

  # tuple
  def valid?({:tuple, types}) when is_list(types) and length(types) >= 2 do
    Enum.all?(types, &valid?/1)
  end

  # map
  def valid?({:map, types}) when is_map(types) and map_size(types) >= 1 do
    Enum.all?(types, fn {_, type} -> valid?(type) end)
  end

  # enum
  def valid?({:enum, items}) when is_list(items) and length(items) >= 2 do
    Enum.all?(items, &is_atom/1)
  end

  # union
  def valid?({:union, types}) when is_map(types) and map_size(types) >= 2 do
    Enum.all?(types, fn {_, type} -> valid?(type) end)
  end

  # list
  def valid?({:list, type}), do: valid?(type)

  def valid?(_descr), do: false
end
