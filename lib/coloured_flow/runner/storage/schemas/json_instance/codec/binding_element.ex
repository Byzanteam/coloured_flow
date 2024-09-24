defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.BindingElement do
  @moduledoc false

  alias ColouredFlow.Enactment.BindingElement

  use ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec,
    codec_spec: {
      :struct,
      BindingElement,
      [
        transition: :string,
        binding: {:list, {:codec, {&encode_binding/1, &decode_binding/1}}},
        to_consume: {:list, {:codec, Codec.Marking}}
      ]
    }

  @spec binding_codec_spec() :: Codec.codec_spec()
  def binding_codec_spec do
    {:codec, {&encode_binding/1, &decode_binding/1}}
  end

  defp encode_binding({variable, value}) do
    %{
      "variable" => Codec.encode_atom(variable),
      "value" => Codec.ColourSet.encode_value(value)
    }
  end

  defp decode_binding(%{"variable" => variable, "value" => value}) do
    {Codec.decode_atom(variable), Codec.ColourSet.decode_value(value)}
  end
end
