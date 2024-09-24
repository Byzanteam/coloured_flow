defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.Transition do
  @moduledoc false

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Transition

  use ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec,
    codec_spec: {
      :struct,
      Transition,
      [
        name: :string,
        guard: {:codec, Codec.Expression},
        action: {
          :struct,
          Action,
          [
            outputs: {:list, {:list, {:codec, {&encode_output/1, &decode_output/1}}}},
            code: {:codec, Codec.Expression}
          ]
        }
      ]
    }

  defp encode_output({:cpn_output_variable, {var_name, meta}}) do
    %{
      "type" => "cpn_bind_variable",
      "variable" => %{
        "name" => Codec.encode_atom(var_name),
        "meta" => Enum.map(meta, fn {key, value} -> {Codec.encode_atom(key), value} end)
      }
    }
  end

  defp encode_output(value) do
    %{
      "type" => "literal",
      "value" => Codec.ColourSet.encode_value(value)
    }
  end

  defp decode_output(%{
         "type" => "cpn_bind_variable",
         "variable" => %{"name" => var_name, "meta" => meta}
       }) do
    {
      :cpn_output_variable,
      {
        Codec.decode_atom(var_name),
        Enum.map(meta, fn {key, value} -> {Codec.decode_atom(key), value} end)
      }
    }
  end

  defp decode_output(%{"type" => "literal", "value" => value}) do
    Codec.ColourSet.decode_value(value)
  end
end
