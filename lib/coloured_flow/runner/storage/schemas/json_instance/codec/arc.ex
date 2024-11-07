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

  @impl Codec
  def decode(data, options) when is_map(data) do
    case super(data, options) do
      %Arc{orientation: :p_to_t} = arc ->
        %Arc{arc | bindings: Arc.build_bindings!(arc.expression)}

      %Arc{orientation: :t_to_p} = arc ->
        arc
    end
  end
end
