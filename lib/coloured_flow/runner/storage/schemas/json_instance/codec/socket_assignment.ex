defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.SocketAssignment do
  @moduledoc false

  alias ColouredFlow.Definition.SocketAssignment

  use ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec,
    codec_spec: {
      :struct,
      SocketAssignment,
      [
        socket: :string,
        port: :string
      ]
    }
end
