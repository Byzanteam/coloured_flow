defmodule ColouredFlow.Runner.Telemetry.LooseMapCodec do
  @moduledoc false

  # This codec is for encoding and decoding map data loosely.
  # It does not enforce all keys to be present in the map,
  # it simply skips the keys that are not present in the specification.

  alias ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec

  @behaviour Codec

  @impl Codec
  def encode(data, options) when is_list(options) do
    Map.new(data, fn {key, value} ->
      spec = Keyword.fetch!(options, key)
      {key, Codec.encode(spec, value)}
    end)
  end

  @impl Codec
  def decode(data, options) when is_list(options) do
    fields_spec = build_fields_spec(options)

    Map.new(data, fn {key, value} ->
      {key, spec} = Map.fetch!(fields_spec, key)
      {key, Codec.decode(spec, value)}
    end)
  end

  defp build_fields_spec(options) do
    options
    |> Enum.flat_map(fn {key, spec} ->
      [{key, {key, spec}}, {Atom.to_string(key), {key, spec}}]
    end)
    |> Map.new()
  end
end
