defmodule ColouredFlow.Definition.Constant do
  @moduledoc """
  A constant is a named value that can never be changed, can be used in
  expressions.

  ## Examples

      colset user() :: %{name: binary(), age: int()}
      colset user_list() :: list(user())

      # constant
      val all_users :: user_list() = [
        %{name: "Alice", age: 20},
        %{name: "Bob", age: 30}
      ]
  """

  use TypedStructor

  alias ColouredFlow.Definition.ColourSet

  @type name() :: atom()

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :name, name()
    field :colour_set, ColourSet.name()

    field :value, ColourSet.value(), doc: "a quoted **literal** expression"
  end
end
