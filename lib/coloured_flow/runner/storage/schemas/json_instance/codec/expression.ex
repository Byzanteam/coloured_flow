defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.Expression do
  @moduledoc false

  alias ColouredFlow.Definition.Expression

  use ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec

  @impl Codec
  def encode(%Expression{} = expression, _options) do
    %{"code" => expression.code}
  end

  @impl Codec
  def decode(%{"code" => code}, _options) do
    Expression.build!(code)
  end
end
