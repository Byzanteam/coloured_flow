defmodule ColouredFlow.EnabledBindingElements.BindingTest do
  use ExUnit.Case, async: true
  doctest ColouredFlow.EnabledBindingElements.Binding, import: true

  alias ColouredFlow.EnabledBindingElements.Binding
  alias ColouredFlow.MultiSet

  describe "match" do
    test "works with literal coefficient" do
      assert [] === Binding.match({1, true}, quote(do: {2, true}))
      assert [[]] === Binding.match({1, true}, quote(do: {1, true}))
      assert [[], [], []] === Binding.match({3, true}, quote(do: {1, true}))
      assert [[x: true]] === Binding.match({1, true}, quote(do: {1, x}), __MODULE__)

      assert [[x: :foo, y: :bar]] ===
               Binding.match({1, {:foo, :bar}}, quote(do: {1, {x, y}}), __MODULE__)

      assert [[x: true], [x: true]] ===
               Binding.match({5, true}, quote(do: {2, x}), __MODULE__)
    end

    test "works with variable coefficient" do
      assert [[x: 0], [x: 1]] === Binding.match({1, true}, quote(do: {x, true}), __MODULE__)

      assert [[x: 1]] === Binding.match({1, 1}, quote(do: {x, x}), __MODULE__)

      assert [] === Binding.match({1, 2}, quote(do: {x, x}), __MODULE__)

      assert [[x: 0, y: 1], [x: 1, y: 1], [x: 1, y: 1], [x: 2, y: 1]] ===
               Binding.match({2, 1}, quote(do: {x, y}), __MODULE__)

      assert [[x: 2], [x: 2]] ===
               Binding.match({5, 2}, quote(do: {x, x}), __MODULE__)
    end

    test "handle zero" do
      assert [[x: 0]] === Binding.match({1, 0}, quote(do: {0, x}), __MODULE__)

      assert [[x: 0]] === Binding.match({1, 0}, quote(do: {1, x}), __MODULE__)

      assert [[x: 0]] === Binding.match({5, 0}, quote(do: {x, x}), __MODULE__)
    end

    test "guard" do
      assert [[x: 2]] === Binding.match({3, 2}, quote(do: {2, x} when x > 1), __MODULE__)

      assert [
               [rest: [2], x: 2, y: 1],
               [rest: [2], x: 3, y: 1]
             ] ===
               Binding.match(
                 {3, [1, 2]},
                 quote(do: {x, [y | rest]} when x > y and length(rest) === 1),
                 __MODULE__
               )
    end
  end

  describe "match_bag" do
    test "works" do
      assert [[y: 1], [y: 2], [y: 2]] ===
               Binding.match_bag(
                 MultiSet.from_pairs([{2, 1}, {5, 2}]),
                 quote(do: {2, y}),
                 __MODULE__
               )
    end
  end

  describe "apply_constants_to_bind_expr" do
    test "works " do
      expr = quote(do: {x, y})

      bind_expr = Binding.apply_constants_to_bind_expr(expr, %{x: 1})
      assert [[y: 1]] = Binding.match({1, 1}, bind_expr, __MODULE__)
    end

    test "works for guard " do
      expr = quote(do: {x, y} when y > 0)

      bind_expr = Binding.apply_constants_to_bind_expr(expr, %{x: 1})
      assert [[y: 1], [y: 1]] = Binding.match({2, 1}, bind_expr, __MODULE__)

      bind_expr = Binding.apply_constants_to_bind_expr(expr, %{x: 1, y: 1})
      assert [[], []] = Binding.match({2, 1}, bind_expr, __MODULE__)

      bind_expr = Binding.apply_constants_to_bind_expr(expr, %{x: 1, y: 0})
      assert [] = Binding.match({2, 1}, bind_expr, __MODULE__)
    end

    test "works for complex value" do
      expr = quote(do: {x, {:list, [%{name: "Alice"} | users]}})
      user_list = [%{name: "Alice"}, %{name: "Bob"}]

      bind_expr = Binding.apply_constants_to_bind_expr(expr, %{users: [%{name: "Bob"}]})

      assert [
               [x: 0],
               [x: 1],
               [x: 1],
               [x: 2]
             ] = Binding.match({2, {:list, user_list}}, bind_expr, __MODULE__)

      bind_expr = Binding.apply_constants_to_bind_expr(expr, %{})

      assert [
               [users: [%{name: "Bob"}], x: 0],
               [users: [%{name: "Bob"}], x: 1]
             ] = Binding.match({1, {:list, user_list}}, bind_expr, __MODULE__)
    end
  end
end
