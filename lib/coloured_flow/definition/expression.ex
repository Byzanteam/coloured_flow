defmodule ColouredFlow.Definition.Expression do
  @moduledoc """
  An expression is a quoted Elixir expression that can be evaluated
  """

  use TypedStructor

  typed_structor enforce: true do
    field :expr, Macro.t(), doc: "a quoted expression"
  end
end
