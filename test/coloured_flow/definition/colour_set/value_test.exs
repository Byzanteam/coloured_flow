defmodule ColouredFlow.Definition.ColourSet.ValueTest do
  use ExUnit.Case, async: true
  alias ColouredFlow.Definition.ColourSet.Value

  describe "valid?/1" do
    test "works" do
      assert Value.valid?(1)
      assert Value.valid?(1.0)
      assert Value.valid?(true)
      assert Value.valid?("string")
      assert Value.valid?({})

      # tuple
      assert Value.valid?({1, 2})
      assert Value.valid?({:atom, 2})
      refute Value.valid?({1})

      # map
      assert Value.valid?(%{key: 1})
      assert Value.valid?(%{:atom => 1})
      refute Value.valid?(%{1 => 1})
      refute Value.valid?(%{})

      # enum
      assert Value.valid?(:atom)

      # union
      assert Value.valid?({:user, "Alice"})
      assert Value.valid?({:post, %{title: "title"}})
      refute Value.valid?({:tag, {1}})

      # list
      assert Value.valid?([1, 2])
      assert Value.valid?([1])
    end
  end
end
