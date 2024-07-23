defmodule ColouredFlow.Definition.Procedure do
  @moduledoc """
  A procedure(aka function, renamed to avoid conflict with Elixir's function)
  is a named function, that can be used in expressions.
  """

  use TypedStructor

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Expression

  @type name() :: atom()

  typed_structor enforce: true do
    field :name, name()
    field :parameters, [ColourSet.name()], default: []
    field :expression, Expression.t()
    field :result, ColourSet.name()
  end
end
