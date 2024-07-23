defmodule ColouredFlow.Definition.ColouredPetriNet do
  @moduledoc """
  The petri net is consists of places, transitions, arcs,
  """

  use TypedStructor

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Procedure
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable

  typed_structor enforce: true do
    # data types
    field :colour_sets, [ColourSet.t()], default: []

    # net
    field :places, [Place.t()]
    field :transitions, [Transition.t()]
    field :arcs, [Arc.t()]

    # variables
    field :variables, [Variable.t()], default: []
    field :constants, [Constant.t()], default: []

    field :functions, [Procedure.t()], default: []
  end
end
