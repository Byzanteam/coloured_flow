defmodule ColouredFlow.DSLTest do
  use ExUnit.Case, async: true

  import ColouredFlow.MultiSet, only: [sigil_MS: 2]

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Enactment.Marking

  describe "use ColouredFlow.DSL end-to-end" do
    test "produces a valid cpnet/0 from a complete workflow" do
      defmodule SimpleSequenceDSL do
        use ColouredFlow.DSL

        name "Simple Sequence"
        version "1.0.0"

        colset int() :: integer()

        var x :: int()

        place :input, :int
        place :output, :int

        transition :pass_through do
          input :input, bind({1, x}), label: "in"
          output :output, {1, x}, label: "out"
        end
      end

      assert %ColouredPetriNet{} = cpnet = SimpleSequenceDSL.cpnet()

      assert SimpleSequenceDSL.__cpn__(:name) == "Simple Sequence"
      assert SimpleSequenceDSL.__cpn__(:version) == "1.0.0"

      assert length(cpnet.places) == 2
      assert length(cpnet.transitions) == 1
      assert length(cpnet.arcs) == 2
    end
  end

  describe "__cpn__(:initial_markings) reflection" do
    test "returns an empty list when no initial markings are declared" do
      defmodule NoInitialMarkings do
        use ColouredFlow.DSL

        name "NoInitialMarkings"

        colset int() :: integer()

        var x :: int()

        place :input, :int
        place :output, :int

        transition :t do
          input :input, bind({1, x})
          output :output, {1, x}
        end
      end

      assert NoInitialMarkings.__cpn__(:initial_markings) == []
    end

    test "returns %Marking{} structs with string place names and multiset tokens" do
      defmodule WithInitialMarkings do
        use ColouredFlow.DSL

        name "WithInitialMarkings"

        colset int() :: integer()

        var x :: int()

        place :input, :int
        place :output, :int

        initial_marking :input, ~MS[1 2 3]

        transition :t do
          input :input, bind({1, x})
          output :output, {1, x}
        end
      end

      assert [
               %Marking{place: "input", tokens: tokens}
             ] = WithInitialMarkings.__cpn__(:initial_markings)

      assert tokens == ~MS[1 2 3]
    end

    test "accumulates multiple initial_marking declarations across places" do
      defmodule MultipleInitialMarkings do
        use ColouredFlow.DSL

        name "MultipleInitialMarkings"

        colset int() :: integer()

        var x :: int()

        place :input, :int
        place :output, :int

        initial_marking :input, ~MS[1 2]
        initial_marking :output, ~MS[3]

        transition :t do
          input :input, bind({1, x})
          output :output, {1, x}
        end
      end

      markings = MultipleInitialMarkings.__cpn__(:initial_markings)

      assert length(markings) == 2

      input_marking = Enum.find(markings, &(&1.place == "input"))
      output_marking = Enum.find(markings, &(&1.place == "output"))

      assert %Marking{place: "input", tokens: input_tokens} = input_marking
      assert %Marking{place: "output", tokens: output_tokens} = output_marking
      assert input_tokens == ~MS[1 2]
      assert output_tokens == ~MS[3]
    end
  end
end
