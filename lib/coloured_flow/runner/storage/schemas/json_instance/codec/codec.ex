defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec do
  @moduledoc false

  @doc """
  Encodes the given data into a json value.

  Use `map` for more extensibility when updating the data structure.
  """
  @callback encode(struct()) :: map()

  @doc """
  Decodes the given json value into a data struct.

  Use `map` for more extensibility when updating the data structure.
  """
  @callback decode(map()) :: struct()

  defmacro __using__(opts) do
    common_ast =
      quote do
        alias ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec

        @behaviour Codec
      end

    case Keyword.fetch(opts, :codec_spec) do
      {:ok, codec_spec} ->
        quote do
          unquote(common_ast)

          @impl Codec
          def encode(data) do
            Codec.encode(unquote(codec_spec), data)
          end

          @impl Codec
          def decode(data) do
            Codec.decode(unquote(codec_spec), data)
          end

          defoverridable Codec
        end

      :error ->
        common_ast
    end
  end

  @typep struct_module() :: module()
  # codec_module is a module that implements the Codec behaviour
  @typep codec_module() :: module()

  @typep json_value() ::
           integer()
           | boolean()
           | float()
           | binary()
           | [json_value()]
           | %{optional(binary()) => json_value()}

  @type codec_spec(value) ::
          :string
          | :atom
          # set to nil when encoding and decoding
          | :ignore
          | {:struct, struct_module(), Keyword.t(codec_spec(value))}
          | {:list, codec_spec(value)}
          | {:codec, codec_module()}
          | {:codec,
             {
               encoder :: (value -> json_value()),
               decoder :: (json_value() -> value)
             }}

  @spec encode(codec_spec(value), value | nil) :: json_value() | nil when value: var
  def encode(_spec, nil), do: nil

  def encode(spec, value) do
    do_encode(spec, value)
  end

  defp do_encode(:string, value) when is_binary(value), do: value
  defp do_encode(:atom, value) when is_atom(value), do: Atom.to_string(value)
  defp do_encode(:ignore, _value), do: nil

  defp do_encode({:struct, module, fields_spec}, value)
       when is_atom(module) and is_list(fields_spec) and is_struct(value, module) do
    value
    |> Map.from_struct()
    |> Map.new(fn {key, value} ->
      spec = Keyword.fetch!(fields_spec, key)
      {Atom.to_string(key), encode(spec, value)}
    end)
  end

  defp do_encode({:list, spec}, value) when is_list(value) do
    Enum.map(value, &encode(spec, &1))
  end

  defp do_encode({:codec, module}, value) when is_atom(module) do
    module.encode(value)
  end

  defp do_encode({:codec, {encoder, _decoder}}, value) when is_function(encoder, 1) do
    encoder.(value)
  end

  @spec decode(codec_spec(value), json_value() | nil) :: value | nil when value: var
  def decode(spec, value)
  def decode(_spec, nil), do: nil

  def decode(spec, value) do
    do_decode(spec, value)
  end

  defp do_decode(:string, value) when is_binary(value), do: value
  # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
  defp do_decode(:atom, value) when is_binary(value), do: String.to_atom(value)

  defp do_decode({:struct, module, _fields_spec}, value)
       when is_atom(module) and is_struct(value, module) do
    value
  end

  defp do_decode({:struct, module, fields_spec}, value)
       when is_atom(module) and is_list(fields_spec) and is_map(value) do
    fields_spec =
      fields_spec
      |> Enum.flat_map(fn {key, spec} ->
        [{key, {key, spec}}, {Atom.to_string(key), {key, spec}}]
      end)
      |> Map.new()

    value
    |> Enum.map(fn {key, value} ->
      {key, spec} = Map.fetch!(fields_spec, key)
      {key, decode(spec, value)}
    end)
    |> then(&struct(module, &1))
  end

  defp do_decode({:list, spec}, value) when is_list(value) do
    Enum.map(value, &decode(spec, &1))
  end

  defp do_decode({:codec, module}, value) when is_atom(module) do
    module.decode(value)
  end

  defp do_decode({:codec, {_encoder, decoder}}, value) when is_function(decoder, 1) do
    decoder.(value)
  end

  @spec encode_atom(atom()) :: String.t()
  def encode_atom(atom) when is_atom(atom) do
    Atom.to_string(atom)
  end

  @spec decode_atom(String.t()) :: atom()
  def decode_atom(string) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    String.to_atom(string)
  end
end
