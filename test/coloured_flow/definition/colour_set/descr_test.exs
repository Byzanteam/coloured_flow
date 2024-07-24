defmodule ColouredFlow.Definition.ColourSet.DescrTest do
  use ExUnit.Case
  alias ColouredFlow.Definition.ColourSet.Descr

  describe "valid?/1" do
    test "works" do
      assert Descr.valid?({:unit, []})
    end

    test "tuple" do
      assert Descr.valid?({:tuple, [{:integer, []}, {:integer, []}]})
      assert Descr.valid?({:tuple, [{:integer, []}, {:integer, []}, {:integer, []}]})
      refute Descr.valid?({:tuple, [{:integer, []}]})
      refute Descr.valid?({:tuple, []})
    end

    test "map" do
      assert Descr.valid?({:map, %{name: {:binary, []}}})
      assert Descr.valid?({:map, %{name: {:binary, []}, age: {:integer, []}}})
      refute Descr.valid?({:map, %{}})
    end

    test "enum" do
      assert Descr.valid?({:enum, [:female, :male]})
      refute Descr.valid?({:enum, [:female]})
      refute Descr.valid?({:enum, []})
    end

    test "union" do
      assert Descr.valid?({:union, %{integer: {:integer, []}, unit: {:unit, []}}})
      refute Descr.valid?({:union, %{integer: {:integer, []}}})
      refute Descr.valid?({:union, %{}})
    end

    test "list" do
      assert Descr.valid?({:list, {:integer, []}})
      assert Descr.valid?({:list, {:list, {:integer, []}}})
      refute Descr.valid?({:list, {}})
    end

    test "complex" do
      assert Descr.valid?(
               {:union,
                %{
                  integer: {:integer, []},
                  unit: {:unit, []},
                  list: {:list, {:list, {:integer, []}}},
                  map: {
                    :map,
                    %{
                      name: {:binary, []},
                      age: {:integer, []},
                      list: {:list, {:integer, []}},
                      enum: {:enum, [:female, :male]}
                    }
                  }
                }}
             )
    end
  end
end
