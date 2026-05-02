defmodule ColouredFlow.DSL.TransitionTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Transition

  describe "transition/2 block" do
    test "captures guard, action, input, output" do
      defmodule FullTransition do
        use ColouredFlow.DSL

        name("FullTransition")

        colset int() :: integer()

        var x :: int()

        place(:input, :int)
        place(:output, :int)

        transition :pass_through do
          guard(x > 0)

          input(:input, bind({1, x}), label: "in")
          output(:output, {1, x * 2}, label: "out")

          action do
            :ok
          end
        end
      end

      cpnet = FullTransition.cpnet()

      assert [%Transition{name: "pass_through"} = transition] = cpnet.transitions
      assert transition.guard.code == "x > 0"
      assert transition.guard.vars == [:x]
      assert %Action{payload: payload} = transition.action
      assert payload =~ ":ok"

      assert length(cpnet.arcs) == 2
      [in_arc, out_arc] = cpnet.arcs
      assert in_arc.label == "in"
      assert in_arc.transition == "pass_through"
      assert out_arc.label == "out"
      assert out_arc.transition == "pass_through"
    end

    test "guard outside transition raises" do
      assert_raise CompileError, ~r/guard.+transition/i, fn ->
        defmodule GuardOutside do
          use ColouredFlow.DSL

          name("GuardOutside")

          colset int() :: integer()

          guard(true)
        end
      end
    end

    test "input outside transition raises" do
      assert_raise CompileError, ~r/input.+transition/i, fn ->
        defmodule InputOutside do
          use ColouredFlow.DSL

          name "InputOutside"

          colset int() :: integer()

          var x :: int()

          place :input, :int

          input :input, bind({1, x})
        end
      end
    end

    test "rejects duplicate transition names at compile time" do
      assert_raise CompileError, ~r/duplicate|unique|transition/i, fn ->
        defmodule DuplicateTransitions do
          use ColouredFlow.DSL

          name "DuplicateTransitions"

          colset int() :: integer()

          var x :: int()

          place :input, :int
          place :output, :int

          transition :t do
            input :input, bind({1, x})
            output :output, {1, x}
          end

          transition :t do
            input :input, bind({1, x})
            output :output, {1, x}
          end
        end
      end
    end
  end
end
