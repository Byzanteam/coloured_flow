defmodule ColouredFlow.Enactment.PlaceMarking do
  @moduledoc """
  A place marking is a multi_set of tokens that hold by a place.
  """

  use TypedStructor

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.MultiSet

  typed_structor enforce: true do
    field :place, Place.name()
    field :tokens, MultiSet.t(ColourSet.value())
  end
end
