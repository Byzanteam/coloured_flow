defmodule ColouredFlow.Notation.DeclarationTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Variable

  alias ColouredFlow.Notation.Declaration

  describe "compile" do
    test "works" do
      inscription = """
        colset user :: %{id: integer(), name: binary()}
        var user :: user()
        alice = %{id: 1, name: "Alice"}
        val user :: user() = alice
      """

      user_type =
        ColourSet.Descr.map(
          id: ColourSet.Descr.integer(),
          name: ColourSet.Descr.binary()
        )

      assert {:ok,
              [
                %ColourSet{name: :user, type: ^user_type},
                %Constant{name: :user, colour_set: :user, value: %{id: 1, name: "Alice"}},
                %Variable{name: :user, colour_set: :user}
              ]} = Declaration.compile(inscription)
    end

    test "single declaration" do
      inscription = "colset user :: %{id: integer(), name: binary()}"

      user_type =
        ColourSet.Descr.map(
          id: ColourSet.Descr.integer(),
          name: ColourSet.Descr.binary()
        )

      assert {:ok, [%ColourSet{name: :user, type: ^user_type}]} =
               Declaration.compile(inscription)
    end
  end
end
