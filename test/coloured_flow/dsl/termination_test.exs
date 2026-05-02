defmodule ColouredFlow.DSL.TerminationTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.TerminationCriteria
  alias ColouredFlow.Definition.TerminationCriteria.Markings

  describe "termination/1 block" do
    test "captures on_markings expression" do
      defmodule TerminationFlow do
        use ColouredFlow.DSL

        name("TerminationFlow")

        colset int() :: integer()

        var x :: int()

        place(:input, :int)
        place(:output, :int)

        transition :t do
          input(:input, bind({1, x}))
          output(:output, {1, x})
        end

        termination do
          on_markings do
            match?(%{"output" => out_ms} when multi_set_coefficient(out_ms, 1) >= 5, markings)
          end
        end
      end

      cpnet = TerminationFlow.cpnet()

      assert %TerminationCriteria{markings: %Markings{} = markings} = cpnet.termination_criteria
      assert markings.expression.vars == [:markings]
      assert markings.expression.code =~ "multi_set_coefficient"
    end

    test "on_markings outside termination raises" do
      assert_raise CompileError, ~r/on_markings.+termination/i, fn ->
        defmodule MarkingsOutside do
          use ColouredFlow.DSL

          name("MarkingsOutside")

          colset int() :: integer()

          on_markings do
            true
          end
        end
      end
    end
  end
end
