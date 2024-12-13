defmodule ColouredFlow.Definition.Validators.VariablesValidatorTest do
  use ExUnit.Case, async: true

  import ColouredFlow.Notation.Colset

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Validators.Exceptions.MissingColourSetError
  alias ColouredFlow.Definition.Variable

  alias ColouredFlow.Definition.Validators.VariablesValidator

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
             VariablesValidator.validate(
               [
                 %Variable{name: :count, colour_set: :int},
                 %Variable{name: :count, colour_set: :user}
               ],
               cpnet
             )
  end

  test "invalid", %{cpnet: cpnet} do
    assert {:error, %MissingColourSetError{colour_set: :str}} =
             VariablesValidator.validate(
               [%Variable{name: :count, colour_set: :str}],
               cpnet
             )
  end
end
