defmodule ColouredFlow.EnabledBindingElements.BindingTest do
  use ExUnit.Case, async: true
  doctest ColouredFlow.EnabledBindingElements.Binding, import: true

  alias ColouredFlow.EnabledBindingElements.Binding
  alias ColouredFlow.MultiSet

  describe "match" do
    test "works with literal coefficient" do
      assert [] === Binding.match({1, true}, {{:cpn_bind_literal, 2}, true})
      assert [[]] === Binding.match({1, true}, {{:cpn_bind_literal, 1}, true})
      assert [[], [], []] === Binding.match({3, true}, {{:cpn_bind_literal, 1}, true})
      assert [[x: true]] === Binding.match({1, true}, {{:cpn_bind_literal, 1}, {:x, [], nil}})

      assert [[x: :foo, y: :bar]] ===
               Binding.match(
                 {1, {:foo, :bar}},
                 {{:cpn_bind_literal, 1}, {{:x, [], nil}, {:y, [], nil}}}
               )

      assert [[x: true], [x: true]] ===
               Binding.match({5, true}, {{:cpn_bind_literal, 2}, {:x, [], nil}})
    end

    test "works with variable coefficient" do
      assert [[x: 0], [x: 1]] === Binding.match({1, true}, {{:cpn_bind_variable, {:x, []}}, true})

      assert [[x: 1]] ===
               Binding.match(
                 {1, 1},
                 {{:cpn_bind_variable, {:x, []}}, {:x, [], nil}}
               )

      assert [] ===
               Binding.match(
                 {1, 2},
                 {{:cpn_bind_variable, {:x, []}}, {:x, [], nil}}
               )

      assert [[x: 0, y: 1], [x: 1, y: 1], [x: 2, y: 1]] ===
               Binding.match(
                 {2, 1},
                 {{:cpn_bind_variable, {:x, []}}, {:y, [], nil}}
               )

      assert [[x: 2], [x: 2]] ===
               Binding.match(
                 {5, 2},
                 {{:cpn_bind_variable, {:x, []}}, {:x, [], nil}}
               )
    end

    test "handle zero" do
      assert [[x: 0]] ===
               Binding.match(
                 {1, 0},
                 {{:cpn_bind_literal, 0}, {:x, [], nil}}
               )

      assert [[x: 0]] ===
               Binding.match(
                 {1, 0},
                 {{:cpn_bind_literal, 1}, {:x, [], nil}}
               )

      assert [[x: 0]] ===
               Binding.match(
                 {5, 0},
                 {{:cpn_bind_variable, {:x, []}}, {:x, [], nil}}
               )
    end
  end

  describe "match_bag" do
    test "works" do
      assert [[y: 1], [y: 2], [y: 2]] ===
               Binding.match_bag(
                 MultiSet.from_pairs([{2, 1}, {5, 2}]),
                 {{:cpn_bind_literal, 2}, {:y, [], nil}}
               )
    end
  end
end
