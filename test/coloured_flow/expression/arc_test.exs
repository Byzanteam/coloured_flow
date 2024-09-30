defmodule ColouredFlow.Expression.ArcTest do
  use ExUnit.Case, async: true

  doctest ColouredFlow.Expression.Arc, import: true

  alias ColouredFlow.Expression.Arc

  describe "extract_binding/1" do
    test "works" do
      assert {{:cpn_bind_literal, 1}, {:x, [], __MODULE__}} =
               Arc.extract_binding(quote do: {1, x})

      assert {{:cpn_bind_variable, {:x, []}}, 1} =
               Arc.extract_binding(quote do: {x, 1})

      assert {{:cpn_bind_variable, {:x, []}}, {:y, [], __MODULE__}} =
               Arc.extract_binding(quote do: {x, y})

      assert {{:cpn_bind_literal, 1}, {{:x, [], __MODULE__}, {:y, [], __MODULE__}}} =
               Arc.extract_binding(quote do: {1, {x, y}})

      assert {{:cpn_bind_literal, 1}, [{:|, [], [1, {:y, [], __MODULE__}]}]} =
               Arc.extract_binding(quote do: {1, [1 | y]})

      assert {{:cpn_bind_variable, {:x, []}}, {:{}, [], [{:y, [], __MODULE__}]}} =
               Arc.extract_binding(quote do: {x, {y}})
    end

    test "errors" do
      assert_raise ArgumentError, fn ->
        Arc.extract_binding(quote do: {1.0, x})
      end

      assert_raise ArgumentError, fn ->
        Arc.extract_binding(quote do: {-1, x})
      end

      assert_raise ArgumentError, fn ->
        Arc.extract_binding(quote do: {x, y, z})
      end

      assert_raise ArgumentError, fn ->
        Arc.extract_binding(quote do: {x, y, z})
      end

      assert_raise ArgumentError, fn ->
        Arc.extract_binding(quote do: {1, y + z})
      end
    end
  end
end
