defmodule ColouredFlow.Definition.ActionTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Expression

  describe "build_outputs/1" do
    test "works" do
      assert {:ok, []} === Action.build_outputs(Expression.build!(""))

      assert {:ok, [[1, {:cpn_output_variable, {:x, [line: 1, column: 12]}}]]} ===
               Action.build_outputs(Expression.build!("output {1, x}"))

      assert {:ok, [[1, 2]]} === Action.build_outputs(Expression.build!("output {1, 2}"))

      assert {:ok,
              [
                [0],
                [{:cpn_output_variable, {:x, [line: 2, column: 11]}}]
              ]} ===
               Action.build_outputs(
                 Expression.build!("""
                 if x > 0 do
                   output {x}
                 else
                   output {0}
                 end
                 """)
               )
    end

    test "errors" do
      assert {:error, {[], "All outputs must have the same length", ""}} ===
               Action.build_outputs(
                 Expression.build!("""
                 if x > 0 do
                   output {1, x}
                 else
                   output {0}
                 end
                 """)
               )

      assert_raise RuntimeError, fn ->
        Action.build_outputs(Expression.build!("output x"))
      end
    end
  end
end
