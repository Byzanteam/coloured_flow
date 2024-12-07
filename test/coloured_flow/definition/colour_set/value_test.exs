defmodule ColouredFlow.Definition.ColourSet.ValueTest do
  use ExUnit.Case, async: true
  doctest ColouredFlow.Definition.ColourSet.Value, import: true

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
      refute Value.valid?([1, "a"])
    end
  end

  describe "shape/1" do
    test "works" do
      assert {:ok, :integer} === Value.shape(1)
      assert {:ok, :float} === Value.shape(1.0)
      assert {:ok, :boolean} === Value.shape(true)
      assert {:ok, :binary} === Value.shape("string")
      assert {:ok, :unit} === Value.shape({})
    end

    test "union" do
      assert {:ok, {:union, %{ack: :integer}}} === Value.shape({:ack, 1})
      assert {:ok, {:union, %{data: :binary}}} === Value.shape({:data, "Coloured"})
    end

    test "tuple" do
      assert {:ok, {:tuple, [:integer, :integer]}} === Value.shape({1, 2})
      assert :error === Value.shape({1})
      assert :error === Value.shape({:tag, {1}})
    end

    test "map" do
      assert {:ok, {:map, %{name: :binary, age: :integer}}} ===
               Value.shape(%{name: "Alice", age: 20})
    end

    test "enum" do
      assert {:ok, {:enum, [:ack]}} === Value.shape(:ack)
    end

    test "list" do
      assert {:ok, {:list, :integer}} === Value.shape([1, 2])

      assert {:ok, {:list, {:map, %{name: :binary}}}} ===
               Value.shape([%{name: "Alice"}, %{name: "Bob"}])

      assert {:ok, {:list, {:tuple, [:integer, :integer, :integer]}}} ===
               Value.shape([{1, 2, 3}, {3, 2, 1}])

      assert {:ok, {:list, {:union, %{data: :binary, ack: :integer}}}} ===
               Value.shape([{:ack, 1}, {:data, "Coloured"}])

      assert {:ok, {:list, {:enum, [:male, :female]}}} === Value.shape([:male, :female])

      # empty list
      assert {:ok, :any_list} === Value.shape([])
      assert {:ok, {:list, {:list, :integer}}} === Value.shape([[], [1], []])

      assert :error === Value.shape([:male, "female"])
    end

    test "complex" do
      assert {
               :ok,
               {
                 :map,
                 %{
                   users: {
                     :list,
                     {
                       :map,
                       %{
                         name: :binary,
                         position: {:tuple, [:integer, :integer]},
                         age: :integer
                       }
                     }
                   },
                   messages: {
                     :list,
                     {:union, %{ack: :integer, data: :binary}}
                   },
                   sex: {:list, {:enum, [:male, :female]}}
                 }
               }
             } ===
               Value.shape(%{
                 users: [
                   %{name: "Alice", age: 20, position: {1, 2}},
                   %{name: "Bob", age: 30, position: {10, 2}}
                 ],
                 messages: [
                   {:ack, 1},
                   {:data, "World"}
                 ],
                 sex: [:male, :female]
               })
    end
  end
end
