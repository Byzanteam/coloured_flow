defmodule ColouredFlow.Notation.ColsetTest do
  use ExUnit.Case, async: true

  import ColouredFlow.Notation.Colset

  alias ColouredFlow.Definition.ColourSet

  describe "colset/1" do
    test "works" do
      assert colset(name() :: binary()) === colset(name :: binary())

      assert_raise RuntimeError, ~r/Invalid ColourSet declaration/, fn ->
        Code.eval_quoted(
          quote do
            colset name()
          end
        )
      end

      assert_raise RuntimeError, ~r/Invalid colour set name: `Name`/, fn ->
        Code.eval_quoted(
          quote do
            colset Name :: binary()
          end
        )
      end

      assert_raise RuntimeError, ~r/Invalid colour set name: `Name.name\(\)`/, fn ->
        Code.eval_quoted(
          quote do
            colset Name.name() :: binary()
          end
        )
      end

      assert_raise RuntimeError, ~r/Invalid colour set type/, fn ->
        Code.eval_quoted(
          quote do
            colset name() :: :name
          end
        )
      end
    end

    test "unit" do
      assert %ColourSet{name: :unit, type: {:unit, []}} === colset(unit :: {})
    end

    test "boolean" do
      assert %ColourSet{name: :bool, type: {:boolean, []}} === colset(bool :: boolean())
    end

    test "integer" do
      assert %ColourSet{name: :int, type: {:integer, []}} === colset(int :: integer())
    end

    test "float" do
      assert %ColourSet{name: :real, type: {:float, []}} === colset(real :: float())
    end

    test "string" do
      assert %ColourSet{name: :string, type: {:binary, []}} === colset(string :: binary())
    end

    test "enum" do
      assert %ColourSet{
               name: :day,
               type:
                 {:enum, [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]}
             } ===
               colset(
                 day() ::
                   :monday | :tuesday | :wednesday | :thursday | :friday | :saturday | :sunday
               )

      assert_raise RuntimeError, ~r/The enum item type must be an atom/, fn ->
        Code.eval_quoted(
          quote do
            colset sex() :: :male | "female"
          end
        )
      end
    end

    test "tuple" do
      assert %ColourSet{name: :location, type: {:tuple, [{:float, []}, {:float, []}]}} ===
               colset(location() :: {float(), float()})

      assert %ColourSet{
               name: :location,
               type: {:tuple, [{:binary, []}, {:float, []}, {:float, []}]}
             } ===
               colset(location() :: {binary(), float(), float()})
    end

    test "map" do
      assert %ColourSet{
               name: :user,
               type: {
                 :map,
                 %{name: {:binary, []}, age: {:integer, []}}
               }
             } ===
               colset(user() :: %{name: binary(), age: integer()})

      assert_raise RuntimeError, ~r/Invalid map key/, fn ->
        Code.eval_quoted(
          quote do
            colset user() :: %{"age" => integer()}
          end
        )
      end
    end

    test "union" do
      assert %ColourSet{
               name: :packet,
               type: {
                 :union,
                 %{data: {:binary, []}, ack: {:integer, []}}
               }
             } ===
               colset(packet() :: {:data, binary()} | {:ack, integer()})

      assert %ColourSet{
               name: :packet,
               type: {
                 :union,
                 %{binary: {:binary, []}, integer: {:integer, []}, float: {:float, []}}
               }
             } ===
               colset(packet() :: {:binary, binary()} | {:integer, integer()} | {:float, float()})

      assert_raise RuntimeError, ~r/Invalid union tags, duplicate tags found/, fn ->
        Code.eval_quoted(
          quote do
            colset packet() :: {:data, binary()} | {:data, integer()}
          end
        )
      end
    end

    test "list" do
      assert %ColourSet{
               name: :packet_list,
               type: {:list, {:binary, []}}
             } ===
               colset(packet_list() :: list(binary()))

      assert %ColourSet{
               name: :packet_list,
               type: {:list, {:union, %{binary: {:binary, []}, integer: {:integer, []}}}}
             } ===
               colset(packet_list() :: list({:binary, binary()} | {:integer, integer()}))

      assert %ColourSet{
               name: :packet_list,
               type: {:list, {:enum, [:binary, :integer]}}
             } ===
               colset(packet_list() :: list(:binary | :integer))

      assert_raise RuntimeError, ~r/Invalid list type, only one type is allowed/, fn ->
        Code.eval_quoted(
          quote do
            colset packet_list() :: list(binary(), integer())
          end
        )
      end
    end

    test "complex" do
      alias ColouredFlow.Definition.ColourSet.Descr

      colour_set =
        colset complex() ::
                 {:integer, integer()}
                 | {:unit, {}}
                 | {:list, list(list(integer()))}
                 | {:map,
                    %{
                      name: binary(),
                      age: integer(),
                      list: list(integer()),
                      enum: :female | :male
                    }}

      assert match?(
               %ColourSet{
                 name: :complex,
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
               },
               colour_set
             )

      assert Descr.valid?(colour_set.type)
    end
  end
end
