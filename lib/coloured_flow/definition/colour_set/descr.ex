defmodule ColouredFlow.Definition.ColourSet.Descr do
  @moduledoc """
  The `descr` is used to describe the colour set.
  """

  @type t() :: ColouredFlow.Definition.ColourSet.descr()

  @doc """
  Check if the `descr` is valid.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec of_descr(descr :: term()) :: {:ok, t()} | :error
  def of_descr(descr) do
    if valid?(descr) do
      {:ok, descr}
    else
      :error
    end
  end

  # primitive
  defp valid?({:integer, []}), do: true
  defp valid?({:float, []}), do: true
  defp valid?({:boolean, []}), do: true
  defp valid?({:binary, []}), do: true
  defp valid?({:unit, []}), do: true

  # tuple
  defp valid?({:tuple, types}) when is_list(types) and length(types) >= 2 do
    Enum.all?(types, &valid?/1)
  end

  # map
  defp valid?({:map, types}) when is_map(types) and map_size(types) >= 1 do
    Enum.all?(types, fn {key, type} when is_atom(key) -> valid?(type) end)
  end

  # enum
  defp valid?({:enum, items}) when is_list(items) and length(items) >= 2 do
    Enum.all?(items, &is_atom/1)
  end

  # union
  defp valid?({:union, types}) when is_map(types) and map_size(types) >= 2 do
    Enum.all?(types, fn {tag, type} when is_atom(tag) -> valid?(type) end)
  end

  # list
  defp valid?({:list, type}), do: valid?(type)

  defp valid?(_descr), do: false

  @doc """
  Convert the `descr` to quoted expression.
  """
  @spec to_quoted(t()) :: Macro.t()
  def to_quoted(descr)
  # primitive
  def to_quoted({:integer, []}), do: {:integer, [], []}
  def to_quoted({:float, []}), do: {:float, [], []}
  def to_quoted({:boolean, []}), do: {:boolean, [], []}
  def to_quoted({:binary, []}), do: {:binary, [], []}
  def to_quoted({:unit, []}), do: {:{}, [], []}

  # tuple
  def to_quoted({:tuple, types}) do
    {:{}, [], Enum.map(types, &to_quoted/1)}
  end

  # map
  def to_quoted({:map, types}) do
    {:%{}, [], Enum.map(types, fn {key, type} -> {key, to_quoted(type)} end)}
  end

  # enum
  def to_quoted({:enum, items}) do
    items
    |> Enum.reverse()
    |> Enum.reduce(fn item, acc -> {:|, [], [item, acc]} end)
  end

  # union
  def to_quoted({:union, types}) do
    types
    |> Enum.reverse()
    |> Enum.map(fn {tag, type} -> {tag, to_quoted(type)} end)
    |> Enum.reduce(fn {tag, quoted}, acc -> {:|, [], [{tag, quoted}, acc]} end)
  end

  # list
  def to_quoted({:list, type}) do
    {:list, [], [to_quoted(type)]}
  end
end
