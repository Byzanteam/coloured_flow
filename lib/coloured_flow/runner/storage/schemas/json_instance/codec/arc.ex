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
        bindings: :ignore
      ]
    }

  @impl Codec
  def encode(%Arc{} = arc, options) do
    arc
    |> super(options)
    |> Map.reject(&match?({_key, nil}, &1))
  end
end
