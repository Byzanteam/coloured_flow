defmodule ColouredFlow.Expression.ActionTest do
  use ExUnit.Case, async: true

  doctest ColouredFlow.Expression.Action, import: true

  alias ColouredFlow.Expression.Action

  describe "extract_output/1" do
    test "works" do
      assert [1, {:cpn_output_variable, {:x, []}}] =
               Action.extract_output(quote do: {1, x})

      assert [{:cpn_output_variable, {:x, []}}, 1] =
               Action.extract_output(quote do: {x, 1})

      assert [
               {:cpn_output_variable, {:x, []}},
               {:cpn_output_variable, {:y, []}}
             ] =
               Action.extract_output(quote do: {x, y})

      assert [
               true,
               {:cpn_output_variable, {:x, []}},
               {:cpn_output_variable, {:y, []}},
               {:cpn_output_variable, {:z, []}}
             ] =
               Action.extract_output(quote do: {true, x, y, z})
    end

    test "errors" do
      assert_raise RuntimeError, fn ->
        Action.extract_output(quote do: {{x, y}, z})
      end

      assert_raise RuntimeError, fn ->
        Action.extract_output(quote do: x)
      end
    end
  end
end
