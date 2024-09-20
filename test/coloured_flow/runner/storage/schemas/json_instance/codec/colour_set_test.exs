defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.ColourSetTest do
  use ColouredFlow.Runner.CodecCase, codec: ColourSet, async: true

  alias ColouredFlow.Definition.ColourSet

  describe "descr codec" do
    test "works" do
      descr =
        {:union,
         %{
           integer: {:integer, []},
           unit: {:unit, []},
           list: {:list, {:list, {:integer, []}}},
           tuple: {:tuple, [{:integer, []}, {:integer, []}]},
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

      json = Codec.encode_descr(descr)
      assert descr === Codec.decode_descr(json)
    end
  end

  describe "value codec" do
    test "works" do
      value =
        {:map,
         %{
           name: "Alice",
           age: 1,
           list: [1, 2],
           enum: :female,
           union: {:integer, 1},
           score: 1.0,
           admin: true,
           unit: {}
         }}

      json = Codec.encode_value(value)
      assert value === Codec.decode_value(json)
    end
  end

  describe "codec" do
    test "works" do
      colour_sets = [
        %ColourSet{name: :x, type: {:integer, []}},
        %ColourSet{
          name: :y,
          type:
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
        }
      ]

      assert_codec(colour_sets)
    end
  end
end
