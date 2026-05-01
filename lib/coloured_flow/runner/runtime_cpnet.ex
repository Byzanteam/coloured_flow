defmodule ColouredFlow.Runner.RuntimeCpnet do
  @moduledoc """
  A runtime view over a `ColouredFlow.Definition.ColouredPetriNet`.

  Wraps the original definition and precomputes the indexes used on the runner hot
  path so lookups become `Map.fetch/2` instead of repeated `Enum.find/2` scans
  over the underlying lists.

  Construction is `O(n)` over the size of the cpnet; the caller pays this cost
  once per request (right after
  `ColouredFlow.Runner.Storage.get_flow_by_enactment/1`) and then threads the
  runtime view through the hot path. The struct is intentionally not cached in the
  GenServer state — each runner request rebuilds it from the freshly-fetched
  definition.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable

  typed_structor enforce: true do
    field :definition, ColouredPetriNet.t()
    field :colour_sets, %{ColourSet.name() => ColourSet.t()}
    field :variables, %{Variable.name() => Variable.t()}
    field :transitions, %{Transition.name() => Transition.t()}
    field :places, %{Place.name() => Place.t()}
    field :constants, %{Constant.name() => ColourSet.value()}
    field :of_type_context, ColouredFlow.Definition.ColourSet.Of.context()

    field :arcs_by_transition_orientation,
          %{{Transition.name(), Arc.orientation()} => [{Arc.t(), Place.t()}]}

    field :transitions_by_input_place, %{Place.name() => [Transition.t()]}
  end

  @doc """
  Build a `RuntimeCpnet` view from a raw `ColouredPetriNet` definition.

  The returned struct holds a reference to the original definition plus the
  precomputed indexes used by the runner hot path. The cost is
  `O(arcs + places + transitions + colour_sets + variables + constants)`.
  """
  @spec from_definition(ColouredPetriNet.t()) :: t()
  def from_definition(%ColouredPetriNet{} = cpnet) do
    colour_sets = Map.new(cpnet.colour_sets, &{&1.name, &1})
    variables = Map.new(cpnet.variables, &{&1.name, &1})
    transitions = Map.new(cpnet.transitions, &{&1.name, &1})
    places = Map.new(cpnet.places, &{&1.name, &1})

    constants =
      Map.new(cpnet.constants, fn %Constant{name: name, value: value} -> {name, value} end)

    of_type_context = build_of_type_context(colour_sets)

    arcs_by_transition_orientation = build_arcs_by_transition_orientation(cpnet.arcs, places)

    transitions_by_input_place =
      build_transitions_by_input_place(cpnet.arcs, transitions)

    struct!(
      __MODULE__,
      definition: cpnet,
      colour_sets: colour_sets,
      variables: variables,
      transitions: transitions,
      places: places,
      constants: constants,
      of_type_context: of_type_context,
      arcs_by_transition_orientation: arcs_by_transition_orientation,
      transitions_by_input_place: transitions_by_input_place
    )
  end

  @spec build_of_type_context(%{ColourSet.name() => ColourSet.t()}) ::
          ColouredFlow.Definition.ColourSet.Of.context()
  defp build_of_type_context(colour_sets) do
    types = Map.new(colour_sets, fn {name, %ColourSet{type: type}} -> {name, type} end)

    %{
      fetch_type: fn name ->
        case Map.fetch(types, name) do
          :error -> raise "Colour set with name #{inspect(name)} not found in the petri net."
          {:ok, type} -> {:ok, type}
        end
      end
    }
  end

  @spec build_arcs_by_transition_orientation([Arc.t()], %{Place.name() => Place.t()}) ::
          %{{Transition.name(), Arc.orientation()} => [{Arc.t(), Place.t()}]}
  defp build_arcs_by_transition_orientation(arcs, places) do
    arcs
    |> Enum.reduce(%{}, fn %Arc{} = arc, acc ->
      place =
        Map.get(places, arc.place) ||
          raise "Place with name #{inspect(arc.place)} not found in the petri net."

      key = {arc.transition, arc.orientation}
      Map.update(acc, key, [{arc, place}], &[{arc, place} | &1])
    end)
    |> Map.new(fn {key, entries} -> {key, Enum.reverse(entries)} end)
  end

  @spec build_transitions_by_input_place([Arc.t()], %{Transition.name() => Transition.t()}) ::
          %{Place.name() => [Transition.t()]}
  defp build_transitions_by_input_place(arcs, transitions) do
    arcs
    |> Enum.reduce(%{}, &index_input_arc(&1, &2, transitions))
    |> Map.new(fn {place, ts} -> {place, Enum.reverse(ts)} end)
  end

  defp index_input_arc(%Arc{orientation: :p_to_t} = arc, acc, transitions) do
    case Map.fetch(transitions, arc.transition) do
      {:ok, transition} ->
        Map.update(acc, arc.place, [transition], &prepend_unique(&1, transition))

      :error ->
        acc
    end
  end

  defp index_input_arc(%Arc{}, acc, _transitions), do: acc

  defp prepend_unique(existing, %Transition{name: name} = transition) do
    if Enum.any?(existing, &(&1.name == name)) do
      existing
    else
      [transition | existing]
    end
  end
end
