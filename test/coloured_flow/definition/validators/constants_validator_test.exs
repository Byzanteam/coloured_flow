defmodule ColouredFlow.Definition.Validators.ConstantsValidatorTest do
  use ExUnit.Case, async: true

  import ColouredFlow.Notation.Colset

  alias ColouredFlow.Definition.ColourSet.ColourSetMismatch
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Constant

  alias ColouredFlow.Definition.Validators.ConstantsValidator

  setup do
    cpnet = %ColouredPetriNet{
      colour_sets: [
        colset(int :: integer()),
        colset(user :: %{name: binary(), age: int()})
      ],
      places: [],
      transitions: [],
      arcs: [],
      variables: []
    }

    [cpnet: cpnet]
  end

  test "valid", %{cpnet: cpnet} do
    assert {:ok, _const} =
             ConstantsValidator.validate(
               [
                 %Constant{name: :count, colour_set: :int, value: 2},
                 %Constant{name: :count, colour_set: :user, value: %{name: "Alice", age: 20}}
               ],
               cpnet
             )
  end

  test "invalid", %{cpnet: cpnet} do
    assert {:error, %ColourSetMismatch{colour_set: :int, value: "1"}} =
             ConstantsValidator.validate(
               [%Constant{name: :count, colour_set: :int, value: "1"}],
               cpnet
             )

    assert {:error, %ColourSetMismatch{colour_set: :str, value: "Alice"}} =
             ConstantsValidator.validate(
               [%Constant{name: :count, colour_set: :str, value: "Alice"}],
               cpnet
             )

    assert {
             :error,
             %ColourSetMismatch{
               colour_set: :user,
               value: %{name: "Alice", age: 20, sex: :female}
             }
           } =
             ConstantsValidator.validate(
               [
                 %Constant{
                   name: :count,
                   colour_set: :user,
                   value: %{name: "Alice", age: 20, sex: :female}
                 }
               ],
               cpnet
             )
  end
end
