defmodule ColouredFlow.Definition.ColourSet.OfTest do
  use ExUnit.Case
  alias ColouredFlow.Definition.ColourSet.Of

  describe "of/2" do
    test "works" do
      assert_of_type({}, {:unit, []})
      refute_of_type(nil, {:unit, []})
    end

    test "primitive" do
      assert_of_type(1, {:integer, []})
      refute_of_type(1.0, {:integer, []})
      assert_of_type(1.0, {:float, []})
      refute_of_type(1, {:float, []})
      assert_of_type(true, {:boolean, []})
      assert_of_type(false, {:boolean, []})
      refute_of_type(nil, {:boolean, []})
      assert_of_type("binary", {:binary, []})
      refute_of_type(nil, {:binary, []})
    end

    test "tuple" do
      assert_of_type({1, 2}, {:tuple, [{:integer, []}, {:integer, []}]})
      refute_of_type({1, 2, 3}, {:tuple, [{:integer, []}, {:integer, []}]})
      assert_of_type({1, "Alice"}, {:tuple, [{:integer, []}, {:binary, []}]})
      refute_of_type({1, "Alice"}, {:tuple, [{:integer, []}, {:integer, []}]})
    end

    test "map" do
      assert_of_type(
        %{name: "Alice", age: 20},
        {:map, %{name: {:binary, []}, age: {:integer, []}}}
      )

      # order does not matter
      assert_of_type(
        %{age: 20, name: "Alice"},
        {:map, %{name: {:binary, []}, age: {:integer, []}}}
      )

      refute_of_type(
        %{name: "Alice"},
        {:map, %{name: {:binary, []}, age: {:integer, []}}}
      )

      refute_of_type(
        %{name: "Alice", age: 20},
        {:map, %{name: {:integer, []}, age: {:integer, []}}}
      )

      refute_of_type(
        %{name: "Alice", age: 20, sex: :female},
        {:map, %{name: {:binary, []}, age: {:integer, []}}}
      )

      refute_of_type(
        %{name: "Alice", sex: :female},
        {:map, %{name: {:binary, []}, age: {:integer, []}}}
      )
    end

    test "enum" do
      assert_of_type(:female, {:enum, [:female, :male]})
      assert_of_type(:male, {:enum, [:female, :male]})
      refute_of_type(nil, {:enum, [:female, :male]})
      refute_of_type(:invalid, {:enum, [:female, :male]})
    end

    test "union" do
      type = {:union, %{integer: {:integer, []}, binary: {:binary, []}}}

      assert_of_type({:integer, 1}, type)
      assert_of_type({:binary, "Alice"}, type)
      refute_of_type({:binary, 1}, type)
      refute_of_type(1, type)
      refute_of_type({:float, 1.0}, type)
    end

    test "list" do
      type = {:list, {:integer, []}}
      assert_of_type([1, 2, 3], type)
      assert_of_type([], type)
      refute_of_type([1, "Alice"], type)
    end

    test "complex" do
      type =
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
               enum: {:enum, [:female, :male]},
               union: {
                 :union,
                 %{
                   integer: {:integer, []},
                   binary: {:binary, []}
                 }
               }
             }
           }
         }}

      assert_of_type({:integer, 1}, type)
      assert_of_type({:unit, {}}, type)
      assert_of_type({:list, [[1, 2], [2]]}, type)

      assert_of_type(
        {:map, %{name: "Alice", age: 1, list: [1, 2], enum: :female, union: {:integer, 1}}},
        type
      )

      assert_of_type(
        {:map, %{name: "Alice", age: 1, list: [1, 2], enum: :female, union: {:binary, "Alice"}}},
        type
      )
    end

    test "compound types" do
      # colset data() :: binary()
      # colset ack() :: integer()
      # colset packet() :: {:data, data()} | {:ack, ack()}
      type = {:union, %{data: {:data, []}, ack: {:ack, []}}}

      context = %{
        fetch_type: fn
          :data -> {:ok, {:binary, []}}
          :ack -> {:ok, {:integer, []}}
          _type -> :error
        end
      }

      assert_of_type({:data, "Coloured"}, type, context)
      assert_of_type({:ack, 1}, type, context)
      refute_of_type({:ack, "Coloured"}, type, context)
    end
  end

  defp assert_of_type(value, type, context \\ default_context()) do
    assert {:ok, value} === Of.of_type(value, type, context)
  end

  defp refute_of_type(value, type, context \\ default_context()) do
    assert :error === Of.of_type(value, type, context)
  end

  defp default_context do
    %{fetch_type: fn _name -> :error end}
  end
end
