defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.Arc do
  @moduledoc false

  alias ColouredFlow.Definition.Arc

  use ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec,
    codec_spec: {
      :struct,
      Arc,
      [
        label: :string,
        orientation: :atom,
        transition: :string,
        place: :string,
        expression: {:codec, Codec.Expression},
        bindings: {:list, {:codec, {&encode_arc_binding/1, &decode_arc_binding/1}}}
      ]
    }

  defp encode_arc_binding({coefficent, value}) do
    %{
      "coefficent" => do_encode_arc_binding(coefficent),
      "value" => do_encode_arc_binding(value)
    }
  end

  defp do_encode_arc_binding({:cpn_bind_variable, var_name}) do
    %{
      "type" => "cpn_bind_variable",
      "name" => Codec.encode_atom(var_name)
    }
  end

  defp do_encode_arc_binding(value) do
    %{
      "type" => "literal",
      "value" => Codec.ColourSet.encode_value(value)
    }
  end

  defp decode_arc_binding(%{"coefficent" => coefficent, "value" => value}) do
    {do_decode_arc_binding(coefficent), do_decode_arc_binding(value)}
  end

  defp do_decode_arc_binding(%{"type" => "cpn_bind_variable", "name" => var_name}) do
    {:cpn_bind_variable, Codec.decode_atom(var_name)}
  end

  defp do_decode_arc_binding(%{"type" => "literal", "value" => value}) do
    Codec.ColourSet.decode_value(value)
  end
end
