defmodule ColouredFlow.Validators.Definition.ModuleValidator do
  @moduledoc """
  Validates module definitions and substitution transitions.

  This validator ensures that:
  1. All modules have valid internal structure (valid petri nets)
  2. Port places are properly defined
  3. Substitution transitions correctly reference existing modules
  4. Socket assignments are valid (colour sets match)
  5. There are no circular module references
  6. All referenced modules exist
  """

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.PortPlace
  alias ColouredFlow.Definition.SocketAssignment
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Validators.Exceptions.InvalidModuleError

  @spec validate(ColouredPetriNet.t()) ::
          {:ok, ColouredPetriNet.t()} | {:error, InvalidModuleError.t()}
  def validate(%ColouredPetriNet{modules: []} = cpnet) do
    # No modules to validate, but still check substitution transitions
    validate_substitution_transitions(cpnet)
  end

  def validate(%ColouredPetriNet{} = cpnet) do
    with :ok <- validate_module_names_unique(cpnet),
         :ok <- validate_each_module(cpnet),
         :ok <- validate_no_circular_references(cpnet),
         {:ok, cpnet} <- validate_substitution_transitions(cpnet) do
      {:ok, cpnet}
    end
  end

  # Validate that all module names are unique
  defp validate_module_names_unique(%ColouredPetriNet{modules: modules}) do
    duplicates =
      modules
      |> Enum.group_by(& &1.name)
      |> Enum.filter(fn {_name, list} -> length(list) > 1 end)
      |> Enum.map(fn {name, _list} -> name end)

    if duplicates == [] do
      :ok
    else
      {
        :error,
        InvalidModuleError.exception(
          reason: :duplicate_module_names,
          message: """
          Duplicate module names found:
          #{Enum.join(duplicates, ", ")}
          """
        )
      }
    end
  end

  # Validate each module's internal structure
  defp validate_each_module(%ColouredPetriNet{modules: modules} = cpnet) do
    Enum.reduce_while(modules, :ok, fn module, :ok ->
      case validate_module(module, cpnet) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # Validate a single module
  defp validate_module(%Module{} = module, %ColouredPetriNet{} = cpnet) do
    with :ok <- validate_port_places_unique(module),
         :ok <- validate_internal_places_unique(module),
         :ok <- validate_port_and_internal_places_disjoint(module),
         :ok <- validate_module_arcs(module),
         :ok <- validate_module_colour_sets(module, cpnet) do
      :ok
    end
  end

  # Validate that port place names are unique
  defp validate_port_places_unique(%Module{name: module_name, port_places: port_places}) do
    duplicates =
      port_places
      |> Enum.group_by(& &1.name)
      |> Enum.filter(fn {_name, list} -> length(list) > 1 end)
      |> Enum.map(fn {name, _list} -> name end)

    if duplicates == [] do
      :ok
    else
      {
        :error,
        InvalidModuleError.exception(
          reason: :duplicate_port_places,
          module_name: module_name,
          message: """
          Module "#{module_name}" has duplicate port place names:
          #{Enum.join(duplicates, ", ")}
          """
        )
      }
    end
  end

  # Validate that internal place names are unique
  defp validate_internal_places_unique(%Module{name: module_name, places: places}) do
    duplicates =
      places
      |> Enum.group_by(& &1.name)
      |> Enum.filter(fn {_name, list} -> length(list) > 1 end)
      |> Enum.map(fn {name, _list} -> name end)

    if duplicates == [] do
      :ok
    else
      {
        :error,
        InvalidModuleError.exception(
          reason: :duplicate_internal_places,
          module_name: module_name,
          message: """
          Module "#{module_name}" has duplicate internal place names:
          #{Enum.join(duplicates, ", ")}
          """
        )
      }
    end
  end

  # Validate that port places and internal places have different names
  defp validate_port_and_internal_places_disjoint(%Module{
         name: module_name,
         port_places: port_places,
         places: places
       }) do
    port_names = MapSet.new(port_places, & &1.name)
    internal_names = MapSet.new(places, & &1.name)

    intersection = MapSet.intersection(port_names, internal_names)

    if MapSet.size(intersection) == 0 do
      :ok
    else
      {
        :error,
        InvalidModuleError.exception(
          reason: :overlapping_place_names,
          module_name: module_name,
          message: """
          Module "#{module_name}" has overlapping port and internal place names:
          #{Enum.join(MapSet.to_list(intersection), ", ")}
          Port places and internal places must have different names.
          """
        )
      }
    end
  end

  # Validate that arcs reference valid places (port or internal) and transitions
  defp validate_module_arcs(%Module{name: module_name} = module) do
    all_place_names = MapSet.new(Module.all_places(module), & &1.name)
    transition_names = MapSet.new(module.transitions, & &1.name)

    invalid_arcs =
      Enum.filter(module.arcs, fn %Arc{place: place, transition: transition} ->
        not MapSet.member?(all_place_names, place) or not MapSet.member?(transition_names, transition)
      end)

    if invalid_arcs == [] do
      :ok
    else
      arc_messages =
        Enum.map_join(invalid_arcs, "\n", fn arc ->
          "- Place: #{arc.place}, Transition: #{arc.transition}"
        end)

      {
        :error,
        InvalidModuleError.exception(
          reason: :invalid_arc_references,
          module_name: module_name,
          message: """
          Module "#{module_name}" has arcs referencing non-existent places or transitions:
          #{arc_messages}
          """
        )
      }
    end
  end

  # Validate that module colour sets exist in parent net or are defined in module
  defp validate_module_colour_sets(%Module{name: module_name} = module, %ColouredPetriNet{} =
                                                                           cpnet) do
    parent_colour_sets = MapSet.new(cpnet.colour_sets, & &1.name)
    module_colour_sets = MapSet.new(module.colour_sets, & &1.name)
    all_colour_sets = MapSet.union(parent_colour_sets, module_colour_sets)

    # Check all places reference valid colour sets
    all_places = Module.all_places(module)

    missing_colour_sets =
      Enum.reduce(all_places, MapSet.new(), fn place, acc ->
        colour_set_name =
          case place do
            %Place{colour_set: cs} -> cs
            %PortPlace{colour_set: cs} -> cs
          end

        if MapSet.member?(all_colour_sets, colour_set_name) do
          acc
        else
          MapSet.put(acc, {place.name, colour_set_name})
        end
      end)

    if MapSet.size(missing_colour_sets) == 0 do
      :ok
    else
      messages =
        Enum.map_join(missing_colour_sets, "\n", fn {place_name, colour_set} ->
          "- Place: #{place_name}, Missing colour set: #{colour_set}"
        end)

      {
        :error,
        InvalidModuleError.exception(
          reason: :missing_colour_sets,
          module_name: module_name,
          message: """
          Module "#{module_name}" references non-existent colour sets:
          #{messages}
          """
        )
      }
    end
  end

  # Validate that there are no circular module references
  defp validate_no_circular_references(%ColouredPetriNet{modules: modules}) do
    # Build a dependency graph
    dependency_graph =
      Enum.reduce(modules, %{}, fn module, acc ->
        dependencies =
          module.transitions
          |> Enum.filter(&Transition.substitution?/1)
          |> Enum.map(& &1.subst)

        Map.put(acc, module.name, dependencies)
      end)

    # Check for cycles using DFS
    case find_cycle(dependency_graph) do
      nil ->
        :ok

      cycle ->
        {
          :error,
          InvalidModuleError.exception(
            reason: :circular_module_reference,
            message: """
            Circular module reference detected:
            #{Enum.join(cycle, " -> ")}
            """
          )
        }
    end
  end

  # Find a cycle in the dependency graph using DFS
  defp find_cycle(graph) do
    Enum.find_value(Map.keys(graph), fn start ->
      dfs_cycle(graph, start, MapSet.new(), [])
    end)
  end

  defp dfs_cycle(graph, node, visited, path) do
    cond do
      node in path ->
        # Found a cycle
        [node | Enum.take_while(Enum.reverse(path), &(&1 != node))] |> Enum.reverse()

      MapSet.member?(visited, node) ->
        # Already visited, no cycle from this node
        nil

      true ->
        # Explore neighbors
        neighbors = Map.get(graph, node, [])
        visited = MapSet.put(visited, node)
        path = [node | path]

        Enum.find_value(neighbors, fn neighbor ->
          dfs_cycle(graph, neighbor, visited, path)
        end)
    end
  end

  # Validate all substitution transitions
  defp validate_substitution_transitions(%ColouredPetriNet{} = cpnet) do
    substitution_transitions = ColouredPetriNet.substitution_transitions(cpnet)

    case validate_each_substitution_transition(substitution_transitions, cpnet) do
      :ok -> {:ok, cpnet}
      {:error, _reason} = error -> error
    end
  end

  defp validate_each_substitution_transition(transitions, cpnet) do
    Enum.reduce_while(transitions, :ok, fn transition, :ok ->
      case validate_substitution_transition(transition, cpnet) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # Validate a single substitution transition
  defp validate_substitution_transition(%Transition{} = transition, %ColouredPetriNet{} = cpnet) do
    with :ok <- validate_module_exists(transition, cpnet),
         :ok <- validate_socket_assignments(transition, cpnet) do
      :ok
    end
  end

  # Validate that the referenced module exists
  defp validate_module_exists(%Transition{name: trans_name, subst: module_name}, %ColouredPetriNet{} =
                                                                                    cpnet) do
    if ColouredPetriNet.get_module(cpnet, module_name) do
      :ok
    else
      {
        :error,
        InvalidModuleError.exception(
          reason: :module_not_found,
          module_name: module_name,
          message: """
          Substitution transition "#{trans_name}" references non-existent module "#{module_name}".
          """
        )
      }
    end
  end

  # Validate socket assignments
  defp validate_socket_assignments(%Transition{} = transition, %ColouredPetriNet{} = cpnet) do
    module = ColouredPetriNet.get_module(cpnet, transition.subst)

    with :ok <- validate_all_ports_assigned(transition, module),
         :ok <- validate_socket_places_exist(transition, cpnet),
         :ok <- validate_colour_sets_match(transition, cpnet, module) do
      :ok
    end
  end

  # Validate that all port places are assigned
  defp validate_all_ports_assigned(
         %Transition{name: trans_name, socket_assignments: assignments},
         %Module{name: module_name, port_places: port_places}
       ) do
    assigned_ports = MapSet.new(assignments, & &1.port)
    required_ports = MapSet.new(port_places, & &1.name)

    missing_ports = MapSet.difference(required_ports, assigned_ports)

    if MapSet.size(missing_ports) == 0 do
      :ok
    else
      {
        :error,
        InvalidModuleError.exception(
          reason: :missing_socket_assignments,
          module_name: module_name,
          message: """
          Substitution transition "#{trans_name}" is missing socket assignments for ports:
          #{Enum.join(MapSet.to_list(missing_ports), ", ")}
          """
        )
      }
    end
  end

  # Validate that socket places exist in the parent net
  defp validate_socket_places_exist(
         %Transition{name: trans_name, socket_assignments: assignments},
         %ColouredPetriNet{places: places}
       ) do
    place_names = MapSet.new(places, & &1.name)

    missing_places =
      Enum.filter(assignments, fn %SocketAssignment{socket: socket} ->
        not MapSet.member?(place_names, socket)
      end)

    if missing_places == [] do
      :ok
    else
      messages =
        Enum.map_join(missing_places, "\n", fn assignment ->
          "- Socket: #{assignment.socket}, Port: #{assignment.port}"
        end)

      {
        :error,
        InvalidModuleError.exception(
          reason: :socket_place_not_found,
          message: """
          Substitution transition "#{trans_name}" references non-existent socket places:
          #{messages}
          """
        )
      }
    end
  end

  # Validate that colour sets match between sockets and ports
  defp validate_colour_sets_match(
         %Transition{name: trans_name, socket_assignments: assignments},
         %ColouredPetriNet{places: places},
         %Module{} = module
       ) do
    place_map = Map.new(places, fn place -> {place.name, place} end)

    mismatches =
      Enum.filter(assignments, fn %SocketAssignment{socket: socket, port: port} ->
        socket_place = Map.get(place_map, socket)
        port_place = Module.get_port_place(module, port)

        socket_place && port_place && socket_place.colour_set != port_place.colour_set
      end)

    if mismatches == [] do
      :ok
    else
      messages =
        Enum.map_join(mismatches, "\n", fn assignment ->
          socket_place = Map.get(place_map, assignment.socket)
          port_place = Module.get_port_place(module, assignment.port)

          "- Socket: #{assignment.socket} (#{socket_place.colour_set}) " <>
            "-> Port: #{assignment.port} (#{port_place.colour_set})"
        end)

      {
        :error,
        InvalidModuleError.exception(
          reason: :colour_set_mismatch,
          message: """
          Substitution transition "#{trans_name}" has colour set mismatches:
          #{messages}
          """
        )
      }
    end
  end
end
