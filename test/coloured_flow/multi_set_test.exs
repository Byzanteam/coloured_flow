defmodule ColouredFlow.MultiSetTest do
  use ExUnit.Case
  doctest ColouredFlow.MultiSet, import: true

  alias ColouredFlow.MultiSet

  describe "Enumerable" do
    test "count" do
      multi_set = MultiSet.new(~w[a b c a b a])

      assert 6 === Enum.count(multi_set)
    end

    test "member?" do
      multi_set = MultiSet.new(~w[a b c a b a])

      assert Enum.member?(multi_set, "a")
      refute Enum.member?(multi_set, "d")
    end

    test "slice" do
      multi_set = MultiSet.new(~w[a b c a b a])

      assert ~w[a a b] === Enum.slice(multi_set, 1..3)
    end

    test "map" do
      list = ~w[a b c a b a]
      multi_set = MultiSet.new(list)

      assert ~w[a a a b b c] === Enum.map(multi_set, &Function.identity/1)
    end
  end

  describe "Collectable" do
    test "into" do
      multi_set = MultiSet.new()

      assert MultiSet.new(~w[a b c]) === Enum.into(~w[a b c], multi_set)
    end
  end

  describe "Inspect" do
    test "inspect" do
      assert ~s|ColouredFlow.MultiSet.from_list([{"a", 3}, {"b", 2}, {"c", 1}])| ===
               inspect(MultiSet.new(~w[a b c a b a]))
    end
  end

  describe "sigil" do
    import MultiSet

    test "works" do
      a = :a

      assert MultiSet.from_list([{2, 3}, {:a, 2}, {"a", 1}]) === ~b[(1+1)**3 a**2 "a"**1]
      assert MultiSet.from_list([{:a, 1}, {"a", 1}]) === ~b(a "a")
      assert MultiSet.from_list([]) === ~b()

      assert_raise RuntimeError, ~r/The sigils ~b only accepts pairs/, fn ->
        Code.eval_quoted(quote(do: ~b[URI.parse("/")]))
      end
    end
  end
end
