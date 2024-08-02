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

    test "returnings" do
      assert {:ok, %Expression{returnings: [{1, {:cpn_returning_variable, :a}}]}} =
               Expression.build("""
               return {1, a}
               """)

      assert {:ok, %Expression{returnings: [{0, 1}, {1, {:cpn_returning_variable, :a}}]}} =
               Expression.build("""
               if a > 1 do
                return {1, a}
               else
                return {0, 1}
               end
               """)
    end

    test "returning should be in vars" do
      assert {:error, {[{:line, 2}, {:column, 12}], "missing returning variable in vars: :b", ""}} =
               Expression.build("""
               b = 1
               return {1, b}
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
