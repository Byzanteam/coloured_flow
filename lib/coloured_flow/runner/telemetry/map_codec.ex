defmodule ColouredFlow.Runner.Telemetry.MapCodec do
  @moduledoc false

  # This codec is for encoding and decoding map data.
  # It enforces all keys to be present in the map,
  # for loose version see `ColouredFlow.Runner.Telemetry.LooseMapCodec`.

  alias ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec

  @behaviour Codec

  @impl Codec
  def encode(data, options) when is_list(options) do
    Map.new(options, fn {key, spec} ->
      value = Map.fetch!(data, key)
      {key, Codec.encode(spec, value)}
    end)
  end

  @impl Codec
  def decode(data, options) when is_list(options) do
    Map.new(options, fn {key, spec} ->
      value = map_fetch!(data, key)
      {key, Codec.decode(spec, value)}
    end)
  end

  defp map_fetch!(map, key) when is_atom(key) do
    case Map.fetch(map, Atom.to_string(key)) do
      {:ok, value} -> value
      :error -> Map.fetch!(map, key)
    end
  end
end
