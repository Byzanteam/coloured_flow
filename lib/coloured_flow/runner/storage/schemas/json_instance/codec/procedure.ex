defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.Procedure do
  @moduledoc false

  alias ColouredFlow.Definition.Procedure

  use ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec,
    codec_spec: {
      :struct,
      Procedure,
      [
        name: :atom,
        expression: {:codec, Codec.Expression},
        result: Codec.ColourSet.descr_codec_spec()
      ]
    }
end
