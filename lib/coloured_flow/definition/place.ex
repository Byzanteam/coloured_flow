defmodule ColouredFlow.Definition.Place do
  @moduledoc """
  A place is a location in the petri net where tokens can be
  stored.
  """

  use TypedStructor

  alias ColouredFlow.Definition.ColourSet

  @type name() :: binary()

  typed_structor enforce: true do
    field :name, name()

    field :colour_set, ColourSet.name(),
      doc: "The data type of the tokens that can be stored in the place."
  end
end
