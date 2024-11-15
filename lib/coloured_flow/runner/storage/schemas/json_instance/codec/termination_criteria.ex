defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.TerminationCriteria do
  @moduledoc false

  alias ColouredFlow.Definition.TerminationCriteria

  use ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec,
    codec_spec: {
      :struct,
      TerminationCriteria,
      [
        markings: {
          :struct,
          TerminationCriteria.Markings,
          [expression: {:codec, Codec.Expression}]
        }
      ]
    }
end
