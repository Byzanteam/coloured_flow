defmodule ColouredFlow.EnabledBindingElements.Utils do
  @moduledoc """
  The utils for the enabled binding elements.

  These helpers operate on a `ColouredFlow.Runner.RuntimeCpnet` — the indexed view
  built from a raw `ColouredFlow.Definition.ColouredPetriNet` at the runner-call
  boundary. Lookups are `O(1)` against the precomputed indexes.
  """

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.MultiSet
  alias ColouredFlow.Runner.RuntimeCpnet

  @spec fetch_colour_set!(colour_set :: ColourSet.name(), runtime_cpnet :: RuntimeCpnet.t()) ::
          ColourSet.t()
  def fetch_colour_set!(colour_set, %RuntimeCpnet{colour_sets: colour_sets}) do
    case Map.fetch(colour_sets, colour_set) do
      {:ok, cs} -> cs
      :error -> raise "Colour set with name #{inspect(colour_set)} not found in the petri net."
    end
  end

  @spec fetch_variable!(variable :: Variable.name(), runtime_cpnet :: RuntimeCpnet.t()) ::
          Variable.t()
  def fetch_variable!(variable, %RuntimeCpnet{variables: variables}) do
    case Map.fetch(variables, variable) do
      {:ok, var} -> var
      :error -> raise "Variable with name #{inspect(variable)} not found in the petri net."
    end
  end

  @spec get_arcs_with_place(Transition.t(), Arc.orientation(), RuntimeCpnet.t()) ::
          [{Arc.t(), Place.t()}]
  def get_arcs_with_place(
        %Transition{name: transition_name},
        orientation,
        %RuntimeCpnet{arcs_by_transition_orientation: index}
      )
      when orientation in [:p_to_t, :t_to_p] do
    Map.get(index, {transition_name, orientation}, [])
  end

  @spec get_marking(Place.t(), %{Place.name() => Marking.t()}) :: Marking.t()
  def get_marking(%Place{} = place, markings) do
    Map.get(
      markings,
      place.name,
      %Marking{place: place.name, tokens: MultiSet.new()}
    )
  end

  @spec fetch_transition!(name :: Transition.name(), runtime_cpnet :: RuntimeCpnet.t()) ::
          Transition.t()
  def fetch_transition!(name, %RuntimeCpnet{transitions: transitions}) do
    case Map.fetch(transitions, name) do
      {:ok, transition} -> transition
      :error -> raise "Transition not found: #{name}"
    end
  end

  @spec list_transitions(
          in_places :: Enumerable.t(Place.name()),
          runtime_cpnet :: RuntimeCpnet.t()
        ) :: [Transition.t()]
  def list_transitions(in_places, %RuntimeCpnet{transitions_by_input_place: index}) do
    in_places
    |> Enum.flat_map(fn place_name -> Map.get(index, place_name, []) end)
    |> Enum.uniq_by(& &1.name)
  end
end
