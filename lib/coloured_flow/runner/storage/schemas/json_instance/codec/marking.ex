defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.Marking do
  @moduledoc false

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.MultiSet

  use ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec,
    codec_spec: {
      :struct,
      Marking,
      [
        place: :string,
        tokens: {:codec, {&encode_tokens/1, &decode_tokens/1}}
      ]
    }

  defp encode_tokens(multi_set) when is_struct(multi_set, MultiSet) do
    pairs = MultiSet.to_pairs(multi_set)

    Enum.map(pairs, fn {coefficient, value} ->
      %{
        "coefficient" => coefficient,
        "value" => Codec.ColourSet.encode_value(value)
      }
    end)
  end

  defp decode_tokens(data) when is_struct(data, MultiSet) do
    data
  end

  defp decode_tokens(data) when is_list(data) do
    pairs =
      Enum.map(data, fn %{"coefficient" => coefficient, "value" => value} ->
        {coefficient, Codec.ColourSet.decode_value(value)}
      end)

    MultiSet.from_pairs(pairs)
  end
end
