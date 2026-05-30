defmodule ColouredFlowDashboard.BindingInspectorTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Variable
  alias ColouredFlow.EnabledBindingElements.Computation
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.MultiSet
  alias ColouredFlow.Runner.RuntimeCpnet
  alias ColouredFlowDashboard.BindingInspector

  import ColouredFlow.Builder.DefinitionHelper

  describe "candidate multiplicity matches the engine" do
    test "duplicate tokens produce duplicate candidates (no Enum.uniq)" do
      cpnet = duplicate_token_cpnet()
      markings = %{"src" => %Marking{place: "src", tokens: MultiSet.new([1, 1])}}

      {:ok, info, candidates} = BindingInspector.inspect(cpnet, markings, "trans")

      # Engine path: two identical bindings with x = 1.
      runtime = RuntimeCpnet.from_definition(cpnet)
      transition = Map.fetch!(runtime.transitions, "trans")
      ebes = Computation.list(transition, runtime, markings)

      assert length(ebes) == 2,
             "engine baseline: marking with two identical tokens must yield two enabled binding elements"

      assert info.candidates_count == 2
      assert info.enabled_count == 2
      assert Enum.all?(candidates, &(&1.guard_status == :enabled))
    end
  end

  describe "rejected_by_arc_eval bucket" do
    test "binding whose value fails the place's colour-set check lands in :rejected_by_arc_eval" do
      # Variable colour_set is :str (binary), place colour_set is :int. The
      # marking is hand-crafted with a non-int token to bypass natural type
      # invariants, exercising the inspector path where match_bag + variable
      # validation succeed but `of_type/3` against the place's colour set
      # rejects the resolved value in `check_arc/5`.
      cpnet = arc_eval_failure_cpnet()
      markings = %{"src" => %Marking{place: "src", tokens: MultiSet.new(["weird"])}}

      {:ok, info, candidates} = BindingInspector.inspect(cpnet, markings, "trans")

      assert info.candidates_count == 1
      assert info.rejected_by_arc_eval_count == 1
      assert info.rejected_by_marking_count == 0
      assert info.enabled_count == 0
      assert info.rejected_by_guard_count == 0

      assert [%{guard_status: :rejected_by_arc_eval, reason: reason}] = candidates
      assert reason =~ "Arc on place src"
    end
  end

  defp duplicate_token_cpnet do
    %ColouredPetriNet{
      colour_sets: [%ColourSet{name: :int, type: {:integer, []}}],
      places: [
        %Place{name: "src", colour_set: :int},
        %Place{name: "dst", colour_set: :int}
      ],
      transitions: [build_transition!(name: "trans", guard: "true")],
      arcs: [
        build_arc!(
          label: "in",
          place: "src",
          transition: "trans",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          label: "out",
          place: "dst",
          transition: "trans",
          orientation: :t_to_p,
          expression: "{1, x}"
        )
      ],
      variables: [%Variable{name: :x, colour_set: :int}]
    }
  end

  defp arc_eval_failure_cpnet do
    # NOTE: this CPN intentionally violates the engine's typing rules (the
    # variable's colour_set widens past the place's). The validators would
    # reject it for a real flow; the inspector accepts it as raw structs so
    # this test can exercise the post-match `of_type` failure path.
    %ColouredPetriNet{
      colour_sets: [
        %ColourSet{name: :int, type: {:integer, []}},
        %ColourSet{name: :str, type: {:binary, []}}
      ],
      places: [%Place{name: "src", colour_set: :int}],
      transitions: [build_transition!(name: "trans", guard: "true")],
      arcs: [
        %Arc{
          label: "in",
          place: "src",
          transition: "trans",
          orientation: :p_to_t,
          expression: Arc.build_expression!(:p_to_t, "bind {1, x}")
        }
      ],
      variables: [%Variable{name: :x, colour_set: :str}]
    }
  end
end
