defmodule ColouredFlow.Definition.ExpressionTest do
  use ExUnit.Case, async: true
  alias ColouredFlow.Definition.Expression

  describe "build/1" do
    test "works" do
      assert {:ok, %Expression{vars: []}} = Expression.build("")
      assert {:ok, %Expression{vars: [:a, :b]}} = Expression.build("a + b")

      assert {:ok, %Expression{vars: [:a, :b]}} =
               Expression.build("""
               fun = fn a -> a + b end
               fun.(a)
               """)
    end

    test "return errors" do
      assert {
               :error,
               {[line: 1, column: 7], "syntax error before: ", ""}
             } = Expression.build("a + b +")
    end
  end
end
