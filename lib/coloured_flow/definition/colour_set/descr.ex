defmodule ColouredFlow.Definition.ColourSet.Descr do
  @moduledoc """
  The `descr` is used to describe the colour set.
  """

  @primitive_types ~w[integer float boolean binary unit]a
  @built_in_types @primitive_types ++ ~w[tuple map enum union list]a

  @type t() :: ColouredFlow.Definition.ColourSet.descr()

  @type primitive_type() :: unquote(ColouredFlow.Types.make_sum_type(@primitive_types))
  @type built_in_type() :: unquote(ColouredFlow.Types.make_sum_type(@built_in_types))

  @spec __built_in_types__() :: [built_in_type()]
  def __built_in_types__, do: @built_in_types

  @spec __built_in_types__(:primitive) :: [primitive_type()]
  def __built_in_types__(:primitive), do: @primitive_types

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

  defp valid?(descr) do
    case {match(descr), descr} do
      {{:built_in, type}, _descr} when type in @primitive_types ->
        true

      {{:built_in, :tuple}, {:tuple, types}} ->
        Enum.all?(types, &valid?/1)

      {{:built_in, :map}, {:map, types}} ->
        Enum.all?(types, fn {key, type} when is_atom(key) -> valid?(type) end)

      {{:built_in, :enum}, {:enum, items}} ->
        Enum.all?(items, &is_atom/1)

      {{:built_in, :union}, {:union, types}} ->
        Enum.all?(types, fn {tag, type} when is_atom(tag) -> valid?(type) end)

      {{:built_in, :list}, {:list, type}} ->
        valid?(type)

      {{:compound, _name}, _descr} ->
        true

      {:unknown, _descr} ->
        false
    end
  end

  @doc """
  Match the `descr` to the type.

  There are three types of results:

  - `{:built_in, type}`: The `descr` is a built-in type.
  - `{:compound, name}`: The `descr` is a compound type that needs to be expanded.
  - `:unknown`: The `descr` is unknown.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec match(descr :: term()) ::
          {:built_in, built_in_type()} | {:compound, atom()} | :unknown
  def match(descr)

  for type <- @primitive_types do
    def match({unquote(type), []}), do: {:built_in, unquote(type)}
  end

  def match({:tuple, types}) when is_list(types) and length(types) >= 2,
    do: {:built_in, :tuple}

  def match({:map, types}) when is_map(types) and map_size(types) >= 1,
    do: {:built_in, :map}

  def match({:enum, items}) when is_list(items) and length(items) >= 2,
    do: {:built_in, :enum}

  def match({:union, types}) when is_map(types) and map_size(types) >= 2,
    do: {:built_in, :union}

  def match({:list, type}) do
    case match(type) do
      {:built_in, _type} -> {:built_in, :list}
      {:compound, _name} -> {:built_in, :list}
      :unknown -> :unknown
    end
  end

  # compound types
  def match({name, []}) when is_atom(name) and name not in @built_in_types,
    do: {:compound, name}

  def match(_descr), do: :unknown

  # Type definitions

  @spec integer() :: t()
  def integer, do: {:integer, []}

  @spec float() :: t()
  def float, do: {:float, []}

  @spec boolean() :: t()
  def boolean, do: {:boolean, []}

  @spec binary() :: t()
  def binary, do: {:binary, []}

  @spec unit() :: t()
  def unit, do: {:unit, []}

  @spec tuple(types :: [t()]) :: t()
  def tuple(types) when is_list(types), do: {:tuple, types}

  @spec map(types :: [{atom(), t()}]) :: t()
  def map(types) when is_list(types), do: {:map, Map.new(types)}

  @spec enum(items :: [atom()]) :: t()
  def enum(items) when is_list(items), do: {:enum, items}

  @spec union(types :: [{atom(), t()}]) :: t()
  def union(types) when is_list(types), do: {:union, Map.new(types)}

  @spec list(type :: t()) :: t()
  def list(type), do: {:list, type}

  @spec type(name :: atom()) :: t()
  def type(name), do: {name, []}

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

  # compound types
  def to_quoted({name, []}) when name not in @built_in_types do
    {name, [], []}
  end
end
