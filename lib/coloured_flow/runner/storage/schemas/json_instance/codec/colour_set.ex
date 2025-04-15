defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.ColourSet do
  @moduledoc false

  alias ColouredFlow.Definition.ColourSet

  use ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec,
    codec_spec: {
      :struct,
      ColourSet,
      [
        name: :atom,
        type: {:codec, {&encode_descr/1, &decode_descr/1}}
      ]
    }

  @spec value_codec_spec() :: Codec.codec_spec(ColourSet.value())
  def value_codec_spec do
    {:codec, {&encode_value/1, &decode_value/1}}
  end

  @spec descr_codec_spec() :: Codec.codec_spec(ColourSet.descr())
  def descr_codec_spec do
    {:codec, {&encode_descr/1, &decode_descr/1}}
  end

  @doc """
  Encode the `c:ColouredFlow.Definition.ColourSet.value/0` to a JSON representation.
  """
  @spec encode_value(ColourSet.value()) :: map()
  def encode_value(value) when is_integer(value) do
    %{
      "type" => "integer",
      "args" => value
    }
  end

  def encode_value(value) when is_float(value) do
    %{
      "type" => "float",
      "args" => value
    }
  end

  def encode_value(value) when is_boolean(value) do
    %{
      "type" => "boolean",
      "args" => value
    }
  end

  def encode_value(value) when is_binary(value) do
    %{
      "type" => "binary",
      "args" => value
    }
  end

  def encode_value({}) do
    %{
      "type" => "unit",
      "args" => nil
    }
  end

  # tuple
  # union, because union is a tuple
  def encode_value(tuple) when tuple_size(tuple) >= 2 do
    values = Tuple.to_list(tuple)

    %{
      "type" => "tuple",
      "args" => Enum.map(values, &encode_value/1)
    }
  end

  # map
  def encode_value(map) when map_size(map) >= 1 do
    %{
      "type" => "map",
      "args" =>
        Map.new(map, fn {key, value} ->
          {Atom.to_string(key), encode_value(value)}
        end)
    }
  end

  # enum
  def encode_value(enum) when is_atom(enum) do
    %{
      "type" => "enum",
      "args" => Atom.to_string(enum)
    }
  end

  # list
  def encode_value(list) when is_list(list) do
    %{
      "type" => "list",
      "args" => Enum.map(list, &encode_value/1)
    }
  end

  @primitive_types ~w[integer float boolean binary]a

  @doc """
  Converts the JSON representation to a `t:ColouredFlow.Definition.ColourSet.value/0`.
  """
  @spec decode_value(map()) :: ColourSet.value()
  def decode_value(map)

  for primitive_type <- @primitive_types do
    def decode_value(%{"type" => unquote(Atom.to_string(primitive_type)), "args" => value}),
      do: value
  end

  def decode_value(%{"type" => "unit", "args" => nil}), do: {}

  # tuple and union
  def decode_value(%{"type" => "tuple", "args" => values}) do
    values
    |> Enum.map(&decode_value/1)
    |> List.to_tuple()
  end

  # map
  def decode_value(%{"type" => "map", "args" => values}) do
    Map.new(values, fn {key, value} ->
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      {String.to_atom(key), decode_value(value)}
    end)
  end

  # enum
  def decode_value(%{"type" => "enum", "args" => value}) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    String.to_atom(value)
  end

  # list
  def decode_value(%{"type" => "list", "args" => values}) do
    Enum.map(values, &decode_value/1)
  end

  alias ColouredFlow.Definition.ColourSet.Descr

  @primitive_types ~w[unit integer float boolean binary]a

  @doc """
  Converts the `descr` to a JSON representation.
  """
  @spec encode_descr(ColourSet.descr()) :: map()
  def encode_descr({primitive, _}) when primitive in @primitive_types do
    %{
      "type" => Atom.to_string(primitive),
      "args" => []
    }
  end

  def encode_descr({:tuple, descrs}) when is_list(descrs) do
    %{
      "type" => "tuple",
      "args" => Enum.map(descrs, &encode_descr/1)
    }
  end

  def encode_descr({:map, descrs}) when is_map(descrs) do
    %{
      "type" => "map",
      "args" =>
        Map.new(descrs, fn {key, value} ->
          {Atom.to_string(key), encode_descr(value)}
        end)
    }
  end

  def encode_descr({:enum, values}) when is_list(values) do
    %{
      "type" => "enum",
      "args" => Enum.map(values, &Atom.to_string/1)
    }
  end

  def encode_descr({:union, descrs}) when is_map(descrs) do
    %{
      "type" => "union",
      "args" =>
        Map.new(descrs, fn {tag, value} ->
          {Atom.to_string(tag), encode_descr(value)}
        end)
    }
  end

  def encode_descr({:list, descr}) do
    %{
      "type" => "list",
      "args" => encode_descr(descr)
    }
  end

  def encode_descr({type, []}) when type not in unquote(Descr.__built_in_types__()) do
    %{
      "type" => Atom.to_string(type),
      "args" => []
    }
  end

  @doc """
  Converts the JSON representation to a `descr`.
  """
  @spec decode_descr(map()) :: ColourSet.descr()
  def decode_descr(map) do
    descr = do_decode_descr(map)

    case Descr.of_descr(descr) do
      {:ok, descr} ->
        descr

      :error ->
        raise ArgumentError, """
        Can not convert the JSON representation to a valid `descr`.
        map: #{inspect(map)}
        descr: #{inspect(descr)}
        """
    end
  end

  for type <- @primitive_types do
    defp do_decode_descr(%{"type" => unquote(Atom.to_string(type)), "args" => []}),
      do: {unquote(type), []}
  end

  defp do_decode_descr(%{"type" => "tuple", "args" => descrs}) when is_list(descrs) do
    {:tuple, Enum.map(descrs, &do_decode_descr/1)}
  end

  defp do_decode_descr(%{"type" => "map", "args" => descrs}) when is_map(descrs) do
    {
      :map,
      Map.new(descrs, fn {key, value} ->
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        {String.to_atom(key), do_decode_descr(value)}
      end)
    }
  end

  defp do_decode_descr(%{"type" => "enum", "args" => values}) when is_list(values) do
    {:enum, Enum.map(values, &String.to_atom/1)}
  end

  defp do_decode_descr(%{"type" => "union", "args" => descrs}) when is_map(descrs) do
    {
      :union,
      Map.new(descrs, fn {tag, value} ->
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        {String.to_atom(tag), do_decode_descr(value)}
      end)
    }
  end

  defp do_decode_descr(%{"type" => "list", "args" => descr}) do
    {:list, do_decode_descr(descr)}
  end

  built_in_types = Enum.map(Descr.__built_in_types__(), &Atom.to_string/1)

  # compound types
  defp do_decode_descr(%{"type" => type, "args" => []})
       when type not in unquote(built_in_types) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    {String.to_atom(type), []}
  end
end
