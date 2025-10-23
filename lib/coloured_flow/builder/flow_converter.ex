defmodule ColouredFlow.Builder.FlowConverter do
  @moduledoc """
  Converts ColouredPetriNet flows into reusable modules.

  This module provides utilities to transform existing flows into modules that can be
  instantiated through substitution transitions. This is useful for:

  - Creating reusable workflow components
  - Building module libraries from existing flows
  - Converting standalone flows into composable parts
  - Enabling flow composition and hierarchical workflows

  ## Example

      # You have an existing authentication flow
      auth_flow = %ColouredPetriNet{
        places: [
          %Place{name: "credentials", colour_set: :credentials},
          %Place{name: "success", colour_set: :unit},
          %Place{name: "failure", colour_set: :string}
        ],
        transitions: [...],
        arcs: [...]
      }

      # Convert it to a module, specifying which places are ports
      auth_module = FlowConverter.flow_to_module(
        auth_flow,
        name: "authentication",
        port_specs: [
          {"credentials", :input},
          {"success", :output},
          {"failure", :output}
        ]
      )

      # Now use it in other flows
      main_flow = %ColouredPetriNet{
        modules: [auth_module],
        transitions: [
          build_substitution_transition!(
            name: "do_auth",
            subst: "authentication",
            socket_assignments: [...]
          )
        ]
      }
  """

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.PortPlace

  @type port_spec() :: {Place.name(), PortPlace.port_type()}
  @type convert_options() :: [
          name: Module.name(),
          port_specs: [port_spec()]
        ]

  @doc """
  Converts a ColouredPetriNet flow into a Module.

  ## Parameters

  - `flow`: The ColouredPetriNet to convert
  - `opts`: Conversion options
    - `:name` (required) - The name for the resulting module
    - `:port_specs` (required) - List of `{place_name, port_type}` tuples specifying
      which places should become port places and their types (`:input`, `:output`, or `:io`)

  ## Returns

  A `Module` struct that can be used in other flows.

  ## Examples

      iex> flow = %ColouredPetriNet{
      ...>   places: [
      ...>     %Place{name: "input", colour_set: :string},
      ...>     %Place{name: "output", colour_set: :string},
      ...>     %Place{name: "internal", colour_set: :string}
      ...>   ],
      ...>   transitions: [...],
      ...>   arcs: [...]
      ...> }
      iex> module = FlowConverter.flow_to_module(flow,
      ...>   name: "processor",
      ...>   port_specs: [
      ...>     {"input", :input},
      ...>     {"output", :output}
      ...>   ]
      ...> )
      iex> module.name
      "processor"
      iex> length(module.port_places)
      2
      iex> length(module.places)
      1

  ## Errors

  Raises if:
  - Required options are missing
  - Port specs reference non-existent places
  - A place is specified as both port and internal place
  """
  @spec flow_to_module(ColouredPetriNet.t(), convert_options()) :: Module.t()
  def flow_to_module(%ColouredPetriNet{} = flow, opts) do
    opts = validate_options!(opts)
    name = Keyword.fetch!(opts, :name)
    port_specs = Keyword.fetch!(opts, :port_specs)

    validate_port_specs!(flow, port_specs)

    port_place_names = MapSet.new(port_specs, fn {name, _type} -> name end)

    %Module{
      name: name,
      colour_sets: flow.colour_sets,
      port_places: create_port_places(flow.places, port_specs),
      places: create_internal_places(flow.places, port_place_names),
      transitions: flow.transitions,
      arcs: flow.arcs,
      variables: flow.variables,
      constants: flow.constants,
      functions: flow.functions
    }
  end

  @doc """
  Converts a ColouredPetriNet flow into a Module with automatic port detection.

  This version automatically treats all places that have no incoming arcs as input ports
  and all places that have no outgoing arcs as output ports. Places with both incoming
  and outgoing arcs become internal places.

  ## Parameters

  - `flow`: The ColouredPetriNet to convert
  - `name`: The name for the resulting module

  ## Returns

  A `Module` struct with automatically detected ports.

  ## Examples

      iex> flow = %ColouredPetriNet{
      ...>   places: [
      ...>     %Place{name: "start", colour_set: :unit},      # No incoming -> input
      ...>     %Place{name: "end", colour_set: :unit},        # No outgoing -> output
      ...>     %Place{name: "middle", colour_set: :unit}      # Has both -> internal
      ...>   ],
      ...>   transitions: [%Transition{name: "t1"}],
      ...>   arcs: [
      ...>     %Arc{place: "start", transition: "t1", orientation: :p_to_t, ...},
      ...>     %Arc{place: "middle", transition: "t1", orientation: :t_to_p, ...},
      ...>     %Arc{place: "end", transition: "t1", orientation: :t_to_p, ...}
      ...>   ]
      ...> }
      iex> module = FlowConverter.flow_to_module_auto(flow, "auto_module")
      iex> module.port_places
      # Contains "start" (input) and "end" (output)
  """
  @spec flow_to_module_auto(ColouredPetriNet.t(), Module.name()) :: Module.t()
  def flow_to_module_auto(%ColouredPetriNet{} = flow, name) do
    port_specs = detect_port_specs(flow)
    flow_to_module(flow, name: name, port_specs: port_specs)
  end

  # Private functions

  defp validate_options!(opts) do
    Keyword.validate!(opts, [:name, :port_specs])
  end

  defp validate_port_specs!(%ColouredPetriNet{places: places}, port_specs) do
    place_names = MapSet.new(places, & &1.name)
    port_place_names = MapSet.new(port_specs, fn {name, _type} -> name end)

    # Check if all port specs reference existing places
    missing_places = MapSet.difference(port_place_names, place_names)

    unless MapSet.size(missing_places) == 0 do
      raise ArgumentError, """
      Port specs reference non-existent places: #{Enum.join(missing_places, ", ")}
      Available places: #{Enum.join(place_names, ", ")}
      """
    end

    # Check for duplicate port specs
    port_spec_names = Enum.map(port_specs, fn {name, _type} -> name end)
    duplicates = port_spec_names -- Enum.uniq(port_spec_names)

    unless duplicates == [] do
      raise ArgumentError, """
      Duplicate port specs for places: #{Enum.join(duplicates, ", ")}
      """
    end

    # Validate port types
    Enum.each(port_specs, fn {name, type} ->
      unless type in [:input, :output, :io] do
        raise ArgumentError, """
        Invalid port type #{inspect(type)} for place "#{name}".
        Must be :input, :output, or :io
        """
      end
    end)
  end

  defp create_port_places(places, port_specs) do
    place_map = Map.new(places, fn place -> {place.name, place} end)

    Enum.map(port_specs, fn {place_name, port_type} ->
      place = Map.fetch!(place_map, place_name)

      %PortPlace{
        name: place.name,
        colour_set: place.colour_set,
        port_type: port_type
      }
    end)
  end

  defp create_internal_places(places, port_place_names) do
    Enum.reject(places, fn place ->
      MapSet.member?(port_place_names, place.name)
    end)
  end

  defp detect_port_specs(%ColouredPetriNet{places: places, arcs: arcs}) do
    # Analyze arcs to determine which places are input/output
    place_arc_info =
      Enum.reduce(places, %{}, fn place, acc ->
        Map.put(acc, place.name, %{has_incoming: false, has_outgoing: false})
      end)

    place_arc_info =
      Enum.reduce(arcs, place_arc_info, fn arc, acc ->
        case arc.orientation do
          # Place to Transition - this place has an outgoing arc
          :p_to_t ->
            Map.update!(acc, arc.place, &%{&1 | has_outgoing: true})

          # Transition to Place - this place has an incoming arc
          :t_to_p ->
            Map.update!(acc, arc.place, &%{&1 | has_incoming: true})
        end
      end)

    # Determine port types
    Enum.flat_map(place_arc_info, fn {place_name, info} ->
      cond do
        # No incoming arcs -> input port
        not info.has_incoming and info.has_outgoing ->
          [{place_name, :input}]

        # No outgoing arcs -> output port
        info.has_incoming and not info.has_outgoing ->
          [{place_name, :output}]

        # Has both or neither -> not a port (internal or isolated)
        true ->
          []
      end
    end)
  end

  @doc """
  Validates that a flow can be safely converted to a module.

  Returns `{:ok, warnings}` if conversion is possible, where warnings is a list of
  potential issues that won't prevent conversion but might indicate problems.

  Returns `{:error, reasons}` if conversion would fail.

  ## Examples

      iex> flow = %ColouredPetriNet{...}
      iex> FlowConverter.validate_conversion(flow, port_specs: [...])
      {:ok, []}

      iex> FlowConverter.validate_conversion(bad_flow, port_specs: [...])
      {:error, ["Port spec references non-existent place: foo"]}
  """
  @spec validate_conversion(ColouredPetriNet.t(), convert_options()) ::
          {:ok, [String.t()]} | {:error, [String.t()]}
  def validate_conversion(%ColouredPetriNet{} = flow, opts) do
    warnings = []
    errors = []

    # Check if name is provided
    {errors, warnings} =
      if Keyword.has_key?(opts, :name) do
        {errors, warnings}
      else
        {["Missing required option: name" | errors], warnings}
      end

    # Check if port_specs is provided
    {errors, warnings} =
      if Keyword.has_key?(opts, :port_specs) do
        {errors, warnings}
      else
        {["Missing required option: port_specs" | errors], warnings}
      end

    # Validate port specs if provided
    {errors, warnings} =
      if port_specs = Keyword.get(opts, :port_specs) do
        place_names = MapSet.new(flow.places, & &1.name)
        port_place_names = MapSet.new(port_specs, fn {name, _type} -> name end)
        missing = MapSet.difference(port_place_names, place_names)

        if MapSet.size(missing) > 0 do
          error_msg = "Port specs reference non-existent places: #{Enum.join(missing, ", ")}"
          {[error_msg | errors], warnings}
        else
          {errors, warnings}
        end
      else
        {errors, warnings}
      end

    # Check for isolated places (warning only)
    {errors, warnings} =
      case find_isolated_places(flow) do
        [] ->
          {errors, warnings}

        isolated ->
          warning = "Flow contains isolated places: #{Enum.join(isolated, ", ")}"
          {errors, [warning | warnings]}
      end

    # Check for places that will become internal but might be intended as ports
    {errors, warnings} =
      if port_specs = Keyword.get(opts, :port_specs) do
        port_names = MapSet.new(port_specs, fn {name, _type} -> name end)
        all_place_names = MapSet.new(flow.places, & &1.name)
        internal_count = MapSet.size(MapSet.difference(all_place_names, port_names))

        if internal_count > length(flow.places) * 0.8 do
          warning =
            "More than 80% of places will be internal. " <>
              "Consider using flow_to_module_auto for automatic port detection."

          {errors, [warning | warnings]}
        else
          {errors, warnings}
        end
      else
        {errors, warnings}
      end

    if errors == [] do
      {:ok, Enum.reverse(warnings)}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  defp find_isolated_places(%ColouredPetriNet{places: places, arcs: arcs}) do
    connected_places = MapSet.new(arcs, & &1.place)

    places
    |> Enum.map(& &1.name)
    |> Enum.reject(&MapSet.member?(connected_places, &1))
  end
end
