defmodule ColouredFlow.Definition.ColourSet do
  @external_resource Path.join(__DIR__, "./colour_set.md")
  @moduledoc File.read!(@external_resource)

  use TypedStructor

  @type name() :: atom()
  @typedoc """
  The value should be a literal quoted expression.

  `Macro.quoted_literal?/1` can be used to check if a quoted expression is a literal.

  ## Valid examples:

      iex> %{name: "Alice", age: 20}
      iex> [1, 2, 3]
      iex> 42

  ## Invalid examples:

      iex> %{name: "Alice", age: age}
      iex> [1, 2, number]
  """
  @type value() :: Macro.t()

  typed_structor enforce: true do
    field :name, name()

    field :type, Macro.t(),
      doc: "The type of the colour set, see module documentation for more information."
  end
end
