defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.Occurrence do
  @moduledoc false

  alias ColouredFlow.Enactment.Occurrence

  use ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec,
    codec_spec: {
      :struct,
      Occurrence,
      [
        binding_element: {:codec, Codec.BindingElement},
        free_assignments: {:list, Codec.BindingElement.binding_codec_spec()},
        to_produce: {:list, {:codec, Codec.Marking}}
      ]
    }
end
