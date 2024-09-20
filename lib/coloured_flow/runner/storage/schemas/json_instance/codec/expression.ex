defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.Expression do
  @moduledoc false

  alias ColouredFlow.Definition.Expression

  use ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec

  @impl Codec
  def encode(%Expression{} = expression) do
    %{"code" => expression.code}
  end

  @impl Codec
  def decode(%{"code" => code}) do
    Expression.build!(code)
  end
end
