defmodule ColouredFlow.EnabledBindingElements.Utils do
  @moduledoc """
  The utils for the enabled binding elements.
  """

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.MultiSet

  @spec fetch_colour_set!(colour_set :: ColourSet.name(), cpnet :: ColouredPetriNet.t()) ::
          ColourSet.t()
  def fetch_colour_set!(colour_set, %ColouredPetriNet{} = cpnet) do
    Enum.find(
      cpnet.colour_sets,
      &match?(%ColourSet{name: ^colour_set}, &1)
    ) || raise "Colour set with name #{inspect(colour_set)} not found in the petri net."
  end

  @spec get_arcs_with_place(Transition.t(), Arc.orientation(), ColouredPetriNet.t()) ::
          Enumerable.t({Arc.t(), Place.t()})
  def get_arcs_with_place(%Transition{} = transition, orientation, %ColouredPetriNet{} = cpnet)
      when orientation in [:p_to_t, :t_to_p] do
    %{name: transition_name} = transition

    cpnet.arcs
    |> Stream.flat_map(fn
      %Arc{orientation: ^orientation, transition: ^transition_name} = arc -> [arc]
      %Arc{} -> []
    end)
    |> Stream.map(fn %Arc{place: place_name} = arc ->
      place =
        Enum.find(cpnet.places, &match?(%Place{name: ^place_name}, &1)) ||
          raise "Place with name #{inspect(place_name)} not found in the petri net."

      {arc, place}
    end)
  end

  @spec get_marking(Place.t(), %{Place.name() => Marking.t()}) :: Marking.t()
  def get_marking(%Place{} = place, markings) do
    Map.get(
      markings,
      place.name,
      %Marking{place: place.name, tokens: MultiSet.new()}
    )
  end

  @spec fetch_transition!(name :: Transition.name(), cpnet :: ColouredPetriNet.t()) ::
          Transition.t()
  def fetch_transition!(name, cpnet) do
    case Enum.find(cpnet.transitions, &(&1.name == name)) do
      nil -> raise "Transition not found: #{name}"
      transition -> transition
    end
  end
end
