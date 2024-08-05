defmodule ColouredFlow.Definition.ArcTest do
  use ExUnit.Case, async: true
  doctest ColouredFlow.Definition.Arc, import: true

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.Expression

  test "bindings" do
    assert {:ok, [{1, {:cpn_bind_variable, :a}}]} =
             Arc.build_bindings(Expression.build!("bind {1, a}"))

    assert {:ok, [{0, 1}, {1, {:cpn_bind_variable, :a}}]} =
             Arc.build_bindings(
               Expression.build!("""
               if a > 1 do
                bind {1, a}
               else
                bind {0, 1}
               end
               """)
             )
  end

  test "binding should be in vars" do
    expr =
      Expression.build!("""
      b = 1
      bind {1, b}
      """)

    assert {:error, {[{:line, 2}, {:column, 10}], "missing binding variable in vars: :b", ""}} =
             Arc.build_bindings(expr)
  end

  describe "build_bindings/1" do
    test "works" do
      assert {:ok, [{1, {:a, :b, :c}}]} =
               Arc.build_bindings(Expression.build!("bind {1, {:a, :b, :c}}"))

      assert {
               :ok,
               [{1, {:cpn_bind_variable, :y}}]
             } =
               Arc.build_bindings(Expression.build!("bind {1, y}"))

      assert {
               :ok,
               [{{:cpn_bind_variable, :x}, true}]
             } =
               Arc.build_bindings(Expression.build!("bind {x, true}"))

      assert {
               :ok,
               [
                 {
                   {:cpn_bind_variable, :x},
                   {:cpn_bind_variable, :y}
                 }
               ]
             } =
               Arc.build_bindings(Expression.build!("bind {x, y}"))
    end
  end
end
