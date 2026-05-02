defmodule ColouredFlow.DSL.ArcTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.Arc

  describe "input/2" do
    test "creates a :p_to_t arc with single-line bind" do
      defmodule InputBare do
        use ColouredFlow.DSL

        name("InputBare")

        colset int() :: integer()

        var x :: int()

        place(:input, :int)
        place(:output, :int)

        transition :t do
          input(:input, bind({1, x}))
          output(:output, {1, x})
        end
      end

      cpnet = InputBare.cpnet()
      assert [in_arc, out_arc] = cpnet.arcs
      assert %Arc{orientation: :p_to_t, place: "input", transition: "t"} = in_arc
      assert in_arc.label == nil
      assert in_arc.expression.code =~ "bind"
      assert in_arc.expression.vars == [:x]

      assert %Arc{orientation: :t_to_p, place: "output", transition: "t"} = out_arc
    end
  end

  describe "input/3 with label" do
    test "stores the label" do
      defmodule InputLabel do
        use ColouredFlow.DSL

        name("InputLabel")

        colset int() :: integer()

        var x :: int()

        place(:input, :int)
        place(:output, :int)

        transition :t do
          input(:input, bind({1, x}), label: "in")
          output(:output, {1, x}, label: "out")
        end
      end

      cpnet = InputLabel.cpnet()
      [in_arc, out_arc] = cpnet.arcs

      assert in_arc.label == "in"
      assert out_arc.label == "out"
    end
  end

  describe "input/2 with do block" do
    test "uses block body as the expression, supports label option" do
      defmodule InputBlock do
        use ColouredFlow.DSL

        name("InputBlock")

        colset int() :: integer()

        var x :: int()

        place(:input, :int)
        place(:output, :int)

        transition :t do
          input :input, label: "in" do
            if x > 0, do: bind({1, x}), else: bind({0, x})
          end

          output :output, label: "out" do
            if x > 0, do: {1, x}, else: {0, x}
          end
        end
      end

      cpnet = InputBlock.cpnet()
      [in_arc, out_arc] = cpnet.arcs

      assert in_arc.label == "in"
      assert in_arc.expression.code =~ "bind"
      assert out_arc.label == "out"
    end
  end

  describe "validation" do
    test "rejects p_to_t arc without bind" do
      assert_raise RuntimeError, ~r/missing `bind`/, fn ->
        defmodule MissingBind do
          use ColouredFlow.DSL

          name "MissingBind"

          colset int() :: integer()

          var x :: int()

          place :input, :int
          place :output, :int

          transition :t do
            input :input, {1, x}
            output :output, {1, x}
          end
        end
      end
    end

    test "rejects arc referencing unknown place" do
      # The general StructureValidator surfaces unknown arc endpoints under
      # the `:missing_nodes` reason ("Places: [\"ghost\"]").
      assert_raise CompileError, ~r/missing.+ghost/is, fn ->
        defmodule UnknownArcPlace do
          use ColouredFlow.DSL

          name "UnknownArcPlace"

          colset int() :: integer()

          var x :: int()

          place :input, :int
          place :output, :int

          transition :t do
            input :ghost, bind({1, x})
            output :output, {1, x}
          end
        end
      end
    end

    test "rejects free var not declared as var/1 or constant" do
      assert_raise CompileError, ~r/unbound|unknown_vars|incoming/i, fn ->
        defmodule UnboundVar do
          use ColouredFlow.DSL

          name "UnboundVar"

          colset int() :: integer()

          # x is not declared as var
          place :input, :int
          place :output, :int

          transition :t do
            input :input, bind({1, x})
            output :output, {1, x}
          end
        end
      end
    end
  end
end
