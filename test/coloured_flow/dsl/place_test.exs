defmodule ColouredFlow.DSL.PlaceTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.Place

  describe "place/2 in defworkflow" do
    test "accumulates places into cpnet/0" do
      defmodule TwoPlaces do
        use ColouredFlow.DSL

        name("TwoPlaces")

        colset int() :: integer()

        place(:input, :int)
        place(:output, :int)

        var x :: int()

        transition :pass do
          input(:input, bind({1, x}))
          output(:output, {1, x})
        end
      end

      cpnet = TwoPlaces.cpnet()

      names = Enum.map(cpnet.places, & &1.name)
      assert "input" in names
      assert "output" in names

      assert %Place{name: "input", colour_set: :int} =
               Enum.find(cpnet.places, &(&1.name == "input"))
    end

    test "rejects duplicate place names at compile time" do
      assert_raise CompileError, ~r/duplicate|unique|already/i, fn ->
        defmodule DuplicatePlaces do
          use ColouredFlow.DSL

          name("DuplicatePlaces")

          colset int() :: integer()

          place(:input, :int)
          place(:input, :int)

          var x :: int()

          transition :t do
            input(:input, bind({1, x}))
            output(:input, {1, x})
          end
        end
      end
    end

    test "rejects unknown colour set" do
      assert_raise CompileError, ~r/colour set|undefined|unknown/i, fn ->
        defmodule UnknownColset do
          use ColouredFlow.DSL

          name("UnknownColset")

          colset int() :: integer()

          place(:input, :ghost)

          var x :: int()

          transition :t do
            input(:input, bind({1, x}))
          end
        end
      end
    end
  end
end
