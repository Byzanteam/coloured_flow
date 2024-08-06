defmodule ColouredFlow.Expression.ArcTest do
  use ExUnit.Case, async: true

  doctest ColouredFlow.Expression.Arc, import: true

  alias ColouredFlow.Expression.Arc

  describe "extract_binding/1" do
    test "works" do
      assert {1, {:cpn_bind_variable, {:x, []}}} =
               Arc.extract_binding(quote do: {1, x})

      assert {{:cpn_bind_variable, {:x, []}}, 1} =
               Arc.extract_binding(quote do: {x, 1})

      assert {{:cpn_bind_variable, {:x, []}}, {:cpn_bind_variable, {:y, []}}} =
               Arc.extract_binding(quote do: {x, y})
    end

    test "errors" do
      assert_raise RuntimeError, fn ->
        Arc.extract_binding(quote do: {1.0, x})
      end

      assert_raise RuntimeError, fn ->
        Arc.extract_binding(quote do: {-1, x})
      end

      assert_raise RuntimeError, fn ->
        Arc.extract_binding(quote do: {x, {y}})
      end

      assert_raise RuntimeError, fn ->
        Arc.extract_binding(quote do: {x, y, z})
      end
    end
  end
end
