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

  describe "type definitions" do
    test "works" do
      assert_of_descr(Descr.integer())
      assert_of_descr(Descr.float())
      assert_of_descr(Descr.boolean())
      assert_of_descr(Descr.binary())
      assert_of_descr(Descr.unit())
      assert_of_descr(Descr.tuple([Descr.integer(), Descr.integer()]))
      assert_of_descr(Descr.map(name: Descr.binary(), age: Descr.integer()))
      assert_of_descr(Descr.enum([:foo, :bar]))
      assert_of_descr(Descr.union(integer: Descr.integer(), unit: Descr.unit()))
      assert_of_descr(Descr.list(Descr.integer()))
    end
  end

  describe "to_quoted/1" do
    test "works" do
      assert_to_quoted({:integer, []}, "integer()")
      assert_to_quoted({:float, []}, "float()")
      assert_to_quoted({:boolean, []}, "boolean()")
      assert_to_quoted({:binary, []}, "binary()")
      assert_to_quoted({:unit, []}, "{}")
    end

    test "tuple" do
      assert_to_quoted(
        {:tuple, [{:integer, []}, {:integer, []}]},
        "{integer(), integer()}"
      )

      assert_to_quoted(
        {:tuple, [{:integer, []}, {:integer, []}, {:integer, []}]},
        "{integer(), integer(), integer()}"
      )
    end

    test "map" do
      assert_to_quoted({:map, %{name: {:binary, []}}}, "%{name: binary()}")

      assert_to_quoted(
        {:map, %{name: {:binary, []}, age: {:integer, []}}},
        "%{name: binary(), age: integer()}"
      )
    end

    test "enum" do
      assert_to_quoted({:enum, [:female, :male]}, ":female | :male")
    end

    test "union" do
      assert_to_quoted(
        {:union, %{integer: {:integer, []}, unit: {:unit, []}}},
        "{:integer, integer()} | {:unit, {}}"
      )
    end

    test "list" do
      assert_to_quoted({:list, {:integer, []}}, "list(integer())")
      assert_to_quoted({:list, {:list, {:integer, []}}}, "list(list(integer()))")
    end

    test "complex" do
      descr =
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

      assert_to_quoted(
        descr,
        """
        {:integer, integer()}
        | {:list, list(list(integer()))}
        | {:unit, {}}
        | {:map, %{list: list(integer()), name: binary(), enum: :female | :male, age: integer()}}
        """
      )
    end
  end

  defp assert_of_descr(descr) do
    assert {:ok, descr} == Descr.of_descr(descr)
  end

  defp refute_of_descr(descr) do
    assert :error == Descr.of_descr(descr)
  end

  defp assert_to_quoted(descr, expected) do
    expected = String.trim(expected)

    assert expected === descr |> Descr.to_quoted() |> Macro.to_string()
  end
end
