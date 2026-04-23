defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.PortPlace do
  @moduledoc false

  alias ColouredFlow.Definition.PortPlace

  use ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec,
    codec_spec: {
      :struct,
      PortPlace,
      [
        name: :string,
        colour_set: :atom,
        port_type: :atom
      ]
    }
end
