defmodule ColouredFlow.EnabledBindingElements.Utils do
  @moduledoc """
  The utils for the enabled binding elements.
  """

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable
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

  @spec build_of_type_context(cpnet :: ColouredPetriNet.t()) ::
          ColouredFlow.Definition.ColourSet.Of.context()
  def build_of_type_context(%ColouredPetriNet{} = cpnet) do
    types =
      Map.new(cpnet.colour_sets, fn %ColourSet{name: name, type: type} ->
        {name, type}
      end)

    %{
      fetch_type: fn name ->
        case Map.fetch(types, name) do
          :error -> raise "Colour set with name #{inspect(name)} not found in the petri net."
          {:ok, type} -> {:ok, type}
        end
      end
    }
  end

  @spec fetch_variable!(variable :: Variable.name(), cpnet :: ColouredPetriNet.t()) ::
          Variable.t()
  def fetch_variable!(variable, %ColouredPetriNet{} = cpnet) do
    Enum.find(
      cpnet.variables,
      &match?(%Variable{name: ^variable}, &1)
    ) || raise "Variable with name #{inspect(variable)} not found in the petri net."
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
  def fetch_transition!(name, %ColouredPetriNet{} = cpnet) do
    case Enum.find(cpnet.transitions, &(&1.name == name)) do
      nil -> raise "Transition not found: #{name}"
      transition -> transition
    end
  end

  @spec list_transitions(in_places :: Enumerable.t(Place.name()), cpnet :: ColouredPetriNet.t()) ::
          Enumerable.t(Transition.t())
  def list_transitions(in_places, %ColouredPetriNet{} = cpnet) when is_list(in_places) do
    in_places = MapSet.new(in_places)

    cpnet.arcs
    |> Enum.flat_map(fn
      %Arc{orientation: :p_to_t} = arc ->
        if arc.place in in_places do
          [arc.transition]
        else
          []
        end

      %Arc{} ->
        []
    end)
    |> MapSet.new()
    |> then(fn transition_names ->
      Enum.filter(cpnet.transitions, &MapSet.member?(transition_names, &1.name))
    end)
  end
end
