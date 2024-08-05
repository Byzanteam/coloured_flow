defmodule ColouredFlow.Definition.ArcTest do
  use ExUnit.Case, async: true
  doctest ColouredFlow.Definition.Arc, import: true

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.Expression

  test "returnings" do
    assert {:ok, [{1, {:cpn_returning_variable, :a}}]} =
             Arc.build_returnings(Expression.build!("return {1, a}"))

    assert {:ok, [{0, 1}, {1, {:cpn_returning_variable, :a}}]} =
             Arc.build_returnings(
               Expression.build!("""
               if a > 1 do
                return {1, a}
               else
                return {0, 1}
               end
               """)
             )
  end

  test "returning should be in vars" do
    expr =
      Expression.build!("""
      b = 1
      return {1, b}
      """)

    assert {:error, {[{:line, 2}, {:column, 12}], "missing returning variable in vars: :b", ""}} =
             Arc.build_returnings(expr)
  end

  describe "build_returnings/1" do
    test "works" do
      assert {:ok, [{1, {:a, :b, :c}}]} =
               Arc.build_returnings(Expression.build!("return {1, {:a, :b, :c}}"))

      assert {
               :ok,
               [{1, {:cpn_returning_variable, :y}}]
             } =
               Arc.build_returnings(Expression.build!("return {1, y}"))

      assert {
               :ok,
               [{{:cpn_returning_variable, :x}, true}]
             } =
               Arc.build_returnings(Expression.build!("return {x, true}"))

      assert {
               :ok,
               [
                 {
                   {:cpn_returning_variable, :x},
                   {:cpn_returning_variable, :y}
                 }
               ]
             } =
               Arc.build_returnings(Expression.build!("return {x, y}"))
    end
  end
end
