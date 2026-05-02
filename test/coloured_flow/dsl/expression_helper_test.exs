defmodule ColouredFlow.DSL.ExpressionHelperTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.DSL.ExpressionHelper

  alias ColouredFlow.Definition.Expression

  describe "build_from_ast/1" do
    test "builds an Expression from an AST with no free vars" do
      ast =
        quote do
          1 + 2
        end

      assert %Expression{} = expr = ExpressionHelper.build_from_ast!(ast)
      assert expr.code == "1 + 2"
      assert expr.vars == []
    end

    test "extracts free vars and sorts them" do
      ast =
        quote do
          x + y - z
        end

      assert %Expression{vars: vars} = ExpressionHelper.build_from_ast!(ast)
      assert vars == [:x, :y, :z]
    end

    test "ignores bound vars" do
      ast =
        quote do
          z = x + 1
          z * 2
        end

      assert %Expression{vars: vars} = ExpressionHelper.build_from_ast!(ast)
      assert vars == [:x]
    end

    test "code is the stringified AST" do
      ast =
        quote do
          if x > 0 do
            x
          else
            -x
          end
        end

      assert %Expression{code: code} = ExpressionHelper.build_from_ast!(ast)
      assert is_binary(code)
      assert code =~ "if x > 0"
    end

    test "expression with bind/1 round-trips through Expression.build/1" do
      ast =
        quote do
          bind({1, x})
        end

      assert %Expression{vars: vars} = ExpressionHelper.build_from_ast!(ast)
      assert vars == [:x]
    end
  end

  describe "build_arc_expression!/2" do
    test "builds an :p_to_t arc expression" do
      ast =
        quote do
          bind({1, x})
        end

      assert %Expression{} = expr = ExpressionHelper.build_arc_expression!(:p_to_t, ast)
      assert expr.vars == [:x]
    end

    test "raises for :p_to_t arc without bind/1" do
      ast =
        quote do
          {1, x}
        end

      assert_raise RuntimeError, ~r/missing `bind`/, fn ->
        ExpressionHelper.build_arc_expression!(:p_to_t, ast)
      end
    end

    test "builds an :t_to_p arc expression without bind/1" do
      ast =
        quote do
          {1, x}
        end

      assert %Expression{} = expr = ExpressionHelper.build_arc_expression!(:t_to_p, ast)
      assert expr.vars == [:x]
    end
  end

  describe "free_vars/1" do
    test "extracts a sorted list of free atom-vars" do
      ast =
        quote do
          a + b + c
        end

      assert ExpressionHelper.free_vars(ast) == [:a, :b, :c]
    end

    test "returns empty list when no free vars" do
      ast =
        quote do
          1 + 2 * 3
        end

      assert ExpressionHelper.free_vars(ast) == []
    end
  end
end
