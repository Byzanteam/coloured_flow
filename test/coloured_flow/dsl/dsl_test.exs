defmodule ColouredFlow.DSLTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.ColouredPetriNet

  describe "use ColouredFlow.DSL end-to-end" do
    test "produces a valid cpnet/0 from a complete workflow" do
      defmodule SimpleSequenceDSL do
        use ColouredFlow.DSL

        name("Simple Sequence")
        version("1.0.0")

        colset int() :: integer()

        var x :: int()

        place(:input, :int)
        place(:output, :int)

        transition :pass_through do
          input(:input, bind({1, x}), label: "in")
          output(:output, {1, x}, label: "out")
        end
      end

      assert %ColouredPetriNet{} = cpnet = SimpleSequenceDSL.cpnet()

      assert SimpleSequenceDSL.__cf_name__() == "Simple Sequence"
      assert SimpleSequenceDSL.__cf_version__() == "1.0.0"

      assert length(cpnet.places) == 2
      assert length(cpnet.transitions) == 1
      assert length(cpnet.arcs) == 2
    end
  end
end
