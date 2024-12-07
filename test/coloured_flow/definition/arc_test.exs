defmodule ColouredFlow.Definition.ArcTest do
  use ExUnit.Case, async: true
  doctest ColouredFlow.Definition.Arc, import: true

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.Expression

  describe "p_to_t arcs" do
    expressions = [
      "bind {1, a}",
      """
      if a > 1 do
        bind {1, a}
      else
        bind {0, 1}
      end
      """,
      "bind {1, {:a, :b, :c}}",
      "bind {1, y}",
      "bind {x, true}",
      "bind {x, y}",
      "bind {x, y} when x > y"
    ]

    for expression <- expressions do
      test inspect(expression) do
        assert {:ok, %Expression{}} = Arc.build_expression(:p_to_t, unquote(expression))
      end
    end

    test "missing bind" do
      assert {:error, {[], "missing `bind` in expression", "{a, b}"}} =
               Arc.build_expression(:p_to_t, "{a, b}")
    end
  end

  describe "t_to_p arcs" do
    expressions = [
      """
      if a > 1 do
        {1, a}
      else
        {0, 1}
      end
      """,
      "{x, y}"
    ]

    for expression <- expressions do
      test inspect(expression) do
        assert {:ok, %Expression{}} = Arc.build_expression(:t_to_p, unquote(expression))
      end
    end
  end
end
