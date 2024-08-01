defmodule ColouredFlow.Expression.ReturningTest do
  use ExUnit.Case, async: true

  doctest ColouredFlow.Expression.Returning, import: true

  alias ColouredFlow.Expression.Returning

  describe "extract_returning/1" do
    test "works" do
      assert {1, {:cpn_returning_variable, :x}} = Returning.extract_returning(quote do: {1, x})
      assert {{:cpn_returning_variable, :x}, 1} = Returning.extract_returning(quote do: {x, 1})

      assert {{:cpn_returning_variable, :x}, {:cpn_returning_variable, :y}} =
               Returning.extract_returning(quote do: {x, y})
    end

    test "errors" do
      assert_raise RuntimeError, fn ->
        Returning.extract_returning(quote do: {1.0, x})
      end

      assert_raise RuntimeError, fn ->
        Returning.extract_returning(quote do: {-1, x})
      end

      assert_raise RuntimeError, fn ->
        Returning.extract_returning(quote do: {x, {y}})
      end

      assert_raise RuntimeError, fn ->
        Returning.extract_returning(quote do: {x, y, z})
      end
    end
  end
end
