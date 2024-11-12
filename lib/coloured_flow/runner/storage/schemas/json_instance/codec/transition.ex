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
            payload: :string,
            inputs: {:list, :atom},
            outputs: {:list, :atom}
          ]
        }
      ]
    }
end
