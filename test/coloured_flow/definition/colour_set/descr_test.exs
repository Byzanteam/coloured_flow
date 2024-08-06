defmodule ColouredFlow.Definition.ColourSet.DescrTest do
  use ExUnit.Case
  alias ColouredFlow.Definition.ColourSet.Descr

  describe "of_descr/1" do
    test "works" do
      assert_of_descr({:integer, []})
      assert_of_descr({:float, []})
      assert_of_descr({:boolean, []})
      assert_of_descr({:binary, []})
      assert_of_descr({:unit, []})
    end

    test "tuple" do
      assert_of_descr({:tuple, [{:integer, []}, {:integer, []}]})
      assert_of_descr({:tuple, [{:integer, []}, {:integer, []}, {:integer, []}]})
      refute_of_descr({:tuple, [{:integer, []}]})
      refute_of_descr({:tuple, []})
    end

    test "map" do
      assert_of_descr({:map, %{name: {:binary, []}}})
      assert_of_descr({:map, %{name: {:binary, []}, age: {:integer, []}}})
      refute_of_descr({:map, %{}})
    end

    test "enum" do
      assert_of_descr({:enum, [:female, :male]})
      refute_of_descr({:enum, [:female]})
      refute_of_descr({:enum, []})
    end

    test "union" do
      assert_of_descr({:union, %{integer: {:integer, []}, unit: {:unit, []}}})
      refute_of_descr({:union, %{integer: {:integer, []}}})
      refute_of_descr({:union, %{}})
    end

    test "list" do
      assert_of_descr({:list, {:integer, []}})
      assert_of_descr({:list, {:list, {:integer, []}}})
      refute_of_descr({:list, {}})
    end

    test "complex" do
      assert_of_descr(
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

  defp assert_of_descr(descr) do
    assert {:ok, descr} == Descr.of_descr(descr)
  end

  defp refute_of_descr(descr) do
    assert :error == Descr.of_descr(descr)
  end
end
