defmodule ColouredFlow.Notation.Colset do
  @moduledoc """
  Declare a colour set(`ColouredFlow.Definition.ColourSet`).
  """

  alias ColouredFlow.Definition.ColourSet

  @doc """
  Declare a colour set(`ColouredFlow.Definition.ColourSet`).

  ## Examples

      iex> colset name :: binary()
      %ColouredFlow.Definition.ColourSet{name: :name, type: {:binary, []}}

  See more examples at `ColouredFlow.Definition.ColourSet`.
  """
  defmacro colset({:"::", _meta, [name, type]}) do
    name = decompose_name(name)
    type = decompose_type(type)

    Macro.escape(%ColourSet{name: name, type: type})
  end

  defmacro colset(declaration) do
    raise """
    Invalid ColourSet declaration: #{type_to_string(declaration)}
    See the documentation for valid colour set declarations at `ColouredFlow.Definition.ColourSet`.
    """
  end

  @name_example """
  Valid examples:

      colset name   :: binary()
      colset name() :: binary()

  Invalid examples:

      colset :name        :: binary()
      colset User.name()  :: binary()
      colset "name"       :: binary()
  """
  defp decompose_name(name) do
    case Macro.decompose_call(name) do
      {:__aliases__, _args} ->
        raise """
        Invalid colour set name: `#{type_to_string(name)}`

        #{@name_example}
        """

      {name, _args} ->
        name

      _other ->
        raise """
        Invalid colour set name: `#{type_to_string(name)}`

        #{@name_example}
        """
    end
  end

  # unit
  defp decompose_type({:{}, _meta, []}) do
    {:unit, []}
  end

  # tuple
  defp decompose_type({type1, type2}) do
    {:tuple, [decompose_type(type1), decompose_type(type2)]}
  end

  defp decompose_type({:{}, _meta, types}) do
    {:tuple, Enum.map(types, &decompose_type/1)}
  end

  # map
  defp decompose_type({:%{}, _meta, fields}) do
    map =
      Map.new(fields, fn {key, type} ->
        if is_atom(key) do
          {key, decompose_type(type)}
        else
          raise """
          Invalid map key: `#{type_to_string(key)}`
          """
        end
      end)

    {:map, map}
  end

  # enum
  defp decompose_type({:|, _meta, [item, _item]} = type) when is_atom(item) do
    {:enum, decompose_enum([type])}
  end

  # union
  defp decompose_type({:|, _meta, [{tag, _type}, _item]} = types) when is_atom(tag) do
    {:union, decompose_union([types])}
  end

  # list
  defp decompose_type({:list, _meta, [type]}) do
    {:list, decompose_type(type)}
  end

  defp decompose_type({:list, _meta, types}) do
    raise """
    Invalid list type, only one type is allowed: `#{type_to_string(types)}`
    """
  end

  defp decompose_type(type) do
    case Macro.decompose_call(type) do
      :error ->
        raise """
        Invalid colour set type: `#{type_to_string(type)}`
        """

      call ->
        call
    end
  end

  defp decompose_enum(enum, acc \\ [])

  defp decompose_enum([], acc) do
    Enum.reverse(acc)
  end

  defp decompose_enum([item], acc) when is_atom(item) do
    decompose_enum([], [item | acc])
  end

  defp decompose_enum([{:|, _meta, [item | rest]}], acc) when is_atom(item) do
    decompose_enum(rest, [item | acc])
  end

  defp decompose_enum([type], _acc) do
    raise """
    Invalid enum item type: `#{type_to_string(type)}`
    The enum item type must be an atom.
    """
  end

  defp decompose_union(union, acc \\ [])

  defp decompose_union([{:|, _meta, types}], acc) do
    decompose_union(types, acc)
  end

  defp decompose_union([], acc) do
    duplicate_tags = find_duplicate_tags(acc)

    if length(duplicate_tags) > 0 do
      raise """
      Invalid union tags, duplicate tags found: `#{type_to_string(duplicate_tags)}`
      """
    else
      Map.new(acc)
    end
  end

  defp decompose_union([{tag, type} | rest], acc) when is_atom(tag) do
    decompose_union(rest, [{tag, decompose_type(type)} | acc])
  end

  defp find_duplicate_tags(tags) do
    tags
    |> Enum.frequencies_by(&elem(&1, 0))
    |> Enum.filter(fn {_tag, count} -> count > 1 end)
    |> Enum.map(fn {tag, _count} -> tag end)
  end

  defp type_to_string(quoted), do: Macro.to_string(quoted)
end
