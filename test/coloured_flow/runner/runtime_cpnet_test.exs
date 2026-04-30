defmodule ColouredFlow.Runner.RuntimeCpnetTest do
  use ExUnit.Case, async: true
  use ColouredFlow.DefinitionHelpers

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.EnabledBindingElements.Utils
  alias ColouredFlow.Runner.RuntimeCpnet

  import ColouredFlow.CpnetBuilder, only: [build_cpnet: 1]
  import ColouredFlow.Notation.Colset
  import ColouredFlow.Notation.Val

  describe "from_definition/1" do
    test "indexes colour sets, variables, transitions, and places by name" do
      cpnet = build_cpnet(:simple_sequence)
      runtime_cpnet = RuntimeCpnet.from_definition(cpnet)

      assert runtime_cpnet.definition === cpnet

      assert %{int: %ColourSet{name: :int}} = runtime_cpnet.colour_sets
      assert map_size(runtime_cpnet.colour_sets) === length(cpnet.colour_sets)

      assert %{x: %Variable{name: :x, colour_set: :int}} = runtime_cpnet.variables
      assert map_size(runtime_cpnet.variables) === length(cpnet.variables)

      assert %{"pass_through" => %Transition{name: "pass_through"}} =
               runtime_cpnet.transitions

      assert map_size(runtime_cpnet.transitions) === length(cpnet.transitions)

      assert %{"input" => %Place{name: "input"}, "output" => %Place{name: "output"}} =
               runtime_cpnet.places

      assert map_size(runtime_cpnet.places) === length(cpnet.places)
    end

    test "precomputes constants as a name => value map" do
      cpnet =
        %ColouredPetriNet{
          colour_sets: [colset(int() :: integer())],
          places: [%Place{name: "p", colour_set: :int}],
          transitions: [],
          arcs: [],
          variables: [],
          constants: [
            val(n :: int() = 5),
            val(m :: int() = 7)
          ]
        }

      runtime_cpnet = RuntimeCpnet.from_definition(cpnet)

      assert %{n: 5, m: 7} === runtime_cpnet.constants
    end

    test "of_type_context resolves declared colour sets and raises on unknown ones" do
      cpnet = build_cpnet(:simple_sequence)
      runtime_cpnet = RuntimeCpnet.from_definition(cpnet)

      assert {:ok, {:integer, []}} = runtime_cpnet.of_type_context.fetch_type.(:int)

      assert_raise RuntimeError, ~r/Colour set with name :missing not found/, fn ->
        runtime_cpnet.of_type_context.fetch_type.(:missing)
      end
    end

    test "arcs_by_transition_orientation groups arcs with their resolved place by (transition, orientation)" do
      cpnet = build_cpnet(:parallel_split)
      runtime_cpnet = RuntimeCpnet.from_definition(cpnet)

      ps_inputs =
        Map.fetch!(runtime_cpnet.arcs_by_transition_orientation, {"parallel_split", :p_to_t})

      assert [
               {%Arc{transition: "parallel_split", orientation: :p_to_t, place: "input"},
                %Place{name: "input"}}
             ] = ps_inputs

      ps_outputs =
        Map.fetch!(runtime_cpnet.arcs_by_transition_orientation, {"parallel_split", :t_to_p})

      assert length(ps_outputs) === 2

      out_places = ps_outputs |> Enum.map(fn {_arc, place} -> place.name end) |> Enum.sort()
      assert ["place_1", "place_2"] === out_places

      Enum.each(ps_outputs, fn {%Arc{} = arc, %Place{}} ->
        assert arc.transition === "parallel_split"
        assert arc.orientation === :t_to_p
      end)
    end

    test "transitions_by_input_place lists every transition that has an incoming arc from a place" do
      cpnet = build_cpnet(:deferred_choice)
      runtime_cpnet = RuntimeCpnet.from_definition(cpnet)

      assert [%Transition{name: "pass_through"}] =
               Map.fetch!(runtime_cpnet.transitions_by_input_place, "input")

      place_transitions =
        runtime_cpnet.transitions_by_input_place
        |> Map.fetch!("place")
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert ["deferred_choice_1", "deferred_choice_2"] === place_transitions

      # output places have no outgoing :p_to_t arcs from them, so they shouldn't
      # appear in the index
      refute Map.has_key?(runtime_cpnet.transitions_by_input_place, "output_1")
      refute Map.has_key?(runtime_cpnet.transitions_by_input_place, "output_2")
    end
  end

  describe "Utils helpers consult the indexes" do
    test "fetch_colour_set!, fetch_variable!, fetch_transition! agree with the original lists" do
      cpnet = build_cpnet(:simple_sequence)
      runtime_cpnet = RuntimeCpnet.from_definition(cpnet)

      [%ColourSet{} = expected_cs] = cpnet.colour_sets
      assert expected_cs === Utils.fetch_colour_set!(expected_cs.name, runtime_cpnet)

      [%Variable{} = expected_var] = cpnet.variables
      assert expected_var === Utils.fetch_variable!(expected_var.name, runtime_cpnet)

      [%Transition{} = expected_tr] = cpnet.transitions
      assert expected_tr === Utils.fetch_transition!(expected_tr.name, runtime_cpnet)
    end

    test "fetch_colour_set! raises when the colour set is missing" do
      runtime_cpnet = RuntimeCpnet.from_definition(build_cpnet(:simple_sequence))

      assert_raise RuntimeError,
                   ~r/Colour set with name :missing not found/,
                   fn -> Utils.fetch_colour_set!(:missing, runtime_cpnet) end
    end

    test "get_arcs_with_place returns the same arcs as the previous Enum.find-based version" do
      cpnet = build_cpnet(:parallel_split)
      runtime_cpnet = RuntimeCpnet.from_definition(cpnet)

      ps_transition = Enum.find(cpnet.transitions, &(&1.name == "parallel_split"))

      indexed = Utils.get_arcs_with_place(ps_transition, :t_to_p, runtime_cpnet)
      naive = naive_arcs_with_place(ps_transition, :t_to_p, cpnet)

      assert Enum.sort(indexed) === Enum.sort(naive)
      assert length(indexed) === 2
    end

    test "list_transitions returns the same transitions as the previous arc-scan version, deduped" do
      cpnet = build_cpnet(:deferred_choice)
      runtime_cpnet = RuntimeCpnet.from_definition(cpnet)

      indexed = Utils.list_transitions(["place"], runtime_cpnet)
      naive = naive_list_transitions(["place"], cpnet)

      assert Enum.sort_by(indexed, & &1.name) === Enum.sort_by(naive, & &1.name)
      assert length(indexed) === 2

      # the same place referenced twice in `in_places` shouldn't double-up the result
      indexed_dup = Utils.list_transitions(["place", "place"], runtime_cpnet)
      assert length(indexed_dup) === 2
    end
  end

  # The pre-refactor implementations of the linear-scan variants, kept here as
  # ground truth so the indexed versions remain semantically equivalent.
  defp naive_arcs_with_place(%Transition{name: name}, orientation, cpnet) do
    cpnet.arcs
    |> Enum.flat_map(fn
      %Arc{orientation: ^orientation, transition: ^name} = arc -> [arc]
      %Arc{} -> []
    end)
    |> Enum.map(fn %Arc{place: place_name} = arc ->
      place = Enum.find(cpnet.places, &(&1.name == place_name))
      {arc, place}
    end)
  end

  defp naive_list_transitions(in_places, cpnet) do
    in_places = MapSet.new(in_places)

    cpnet.arcs
    |> Enum.flat_map(fn
      %Arc{orientation: :p_to_t} = arc ->
        if arc.place in in_places, do: [arc.transition], else: []

      %Arc{} ->
        []
    end)
    |> MapSet.new()
    |> then(fn names ->
      Enum.filter(cpnet.transitions, &MapSet.member?(names, &1.name))
    end)
  end
end
