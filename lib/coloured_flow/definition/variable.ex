defmodule ColouredFlow.Definition.Variable do
  @moduledoc """
  A typed variable is a variable that is not bound to any value.
  It can be used in arc annotations, guard expressions, etc.

  ## Examples

      colset user() :: %{name: binary(), age: integer()}

      # variable
      var user  :: user();
  """

  use TypedStructor

  alias ColouredFlow.Definition.ColourSet

  @type name() :: atom()

  typed_structor enforce: true do
    field :name, name()
    field :colour_set, ColourSet.name()
  end
end
