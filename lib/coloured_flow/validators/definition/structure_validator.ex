defmodule ColouredFlow.Validators.Definition.StructureValidator do
  @moduledoc """
  The validator is used to validate weather the Coloured Petri Net structure is correct.

  A well-structured Coloured Petri Net is a Graph that has the following properties:
  1. The Graph has at least one place or one transition.
  2. Transitions and places cannot link to the same type of nodes.
  3. There is at most one directed arc in both directions between a place and a transition.
  4. There can’t be any dangling nodes that aren’t connected to any other nodes.
  """

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Validators.Exceptions.InvalidStructureError

  @typep graph_node() :: {:place, Place.name()} | {:transition, Transition.name()}
  @typep directed_arc() :: {Place.name(), Arc.orientation(), Transition.name()}

  @spec validate(ColouredPetriNet.t()) ::
          {:ok, ColouredPetriNet.t()} | {:error, InvalidStructureError.t()}
  def validate(%ColouredPetriNet{places: [], transitions: []}) do
    {
      :error,
      InvalidStructureError.exception(
        reason: :empty_nodes,
        message: """
        There isn’t a place or transition.
        Please make sure that the graph has at least one place or one transition.
        """
      )
    }
  end

  def validate(%ColouredPetriNet{} = cpnet) do
    with({:ok, arcs} <- get_directed_arcs(cpnet)) do
      connected_nodes = get_connected_nodes(arcs)
      nodes = get_nodes(cpnet)

      cond do
        (diff = MapSet.difference(connected_nodes, nodes)) !== MapSet.new() ->
          {
            :error,
            InvalidStructureError.exception(
              reason: :missing_nodes,
              message: """
              The following nodes are missing from the graph:
              #{nodes_message(diff)}
              """
            )
          }

        (diff = MapSet.difference(nodes, connected_nodes)) !== MapSet.new() ->
          {
            :error,
            InvalidStructureError.exception(
              reason: :dangling_nodes,
              message: """
              There are some dangling nodes that aren’t connected to any other nodes:
              #{nodes_message(diff)}
              """
            )
          }

        true ->
          {:ok, cpnet}
      end
    end
  end

  @spec get_directed_arcs(ColouredPetriNet.t()) ::
          {:ok, MapSet.t(directed_arc())} | {:error, InvalidStructureError.t()}
  defp get_directed_arcs(%ColouredPetriNet{} = cpnet) do
    cpnet.arcs
    |> Enum.reduce({MapSet.new(), []}, fn %Arc{} = arc, {acc, duplicates} ->
      directed_arc = {arc.place, arc.orientation, arc.transition}

      if MapSet.member?(acc, directed_arc) do
        {acc, [arc | duplicates]}
      else
        {MapSet.put(acc, directed_arc), duplicates}
      end
    end)
    |> case do
      {arcs, []} ->
        {:ok, arcs}

      {_arcs, duplicates} ->
        message =
          Enum.map_join(duplicates, "\n", fn
            %Arc{label: nil} = arc ->
              "- #{arc.place}, #{arc.orientation}, #{arc.transition}"

            %Arc{label: label} = arc ->
              "- #{arc.place}, #{arc.orientation}, #{arc.transition}: #{label}"
          end)

        {
          :error,
          InvalidStructureError.exception(
            reason: :duplicate_arcs,
            message: """
            There are duplicate arcs in the graph:
            (in the format: place, orientation, transition, optional label)
            #{message}
            """
          )
        }
    end
  end

  @spec get_nodes(ColouredPetriNet.t()) :: MapSet.t(graph_node())
  defp get_nodes(%ColouredPetriNet{} = cpnet) do
    places = Stream.map(cpnet.places, &{:place, &1.name})
    transitions = Stream.map(cpnet.transitions, &{:transition, &1.name})

    places
    |> Stream.concat(transitions)
    |> MapSet.new()
  end

  @spec get_connected_nodes(MapSet.t(directed_arc())) :: MapSet.t(graph_node())
  defp get_connected_nodes(arcs) do
    arcs
    |> Stream.flat_map(fn {place, _orientation, transition} ->
      [{:place, place}, {:transition, transition}]
    end)
    |> MapSet.new()
  end

  @spec nodes_message(MapSet.t(graph_node())) :: String.t()
  defp nodes_message(nodes) do
    nodes = Enum.group_by(nodes, &elem(&1, 0), &elem(&1, 1))

    missing_places =
      case Map.get(nodes, :place) do
        nil -> nil
        places -> "Places: #{inspect(places)}"
      end

    missing_transitions =
      case Map.get(nodes, :transition) do
        nil -> nil
        transitions -> "Transitions: #{inspect(transitions)}"
      end

    [missing_places, missing_transitions] |> Enum.reject(&is_nil/1) |> Enum.join("\n")
  end
end
