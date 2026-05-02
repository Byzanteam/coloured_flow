defmodule ColouredFlow.Validators.Definition.PlacesValidatorTest do
  use ExUnit.Case, async: true

  import ColouredFlow.Notation.Colset

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Validators.Definition.PlacesValidator
  alias ColouredFlow.Validators.Exceptions.MissingColourSetError

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

  test "valid: each place colour set resolves", %{cpnet: cpnet} do
    cpnet = %{
      cpnet
      | places: [
          %Place{name: "p1", colour_set: :int},
          %Place{name: "p2", colour_set: :user}
        ]
    }

    assert {:ok, ^cpnet} = PlacesValidator.validate(cpnet)
  end

  test "valid: multiple places sharing the same colour set", %{cpnet: cpnet} do
    cpnet = %{
      cpnet
      | places: [
          %Place{name: "a", colour_set: :int},
          %Place{name: "b", colour_set: :int},
          %Place{name: "c", colour_set: :int}
        ]
    }

    assert {:ok, ^cpnet} = PlacesValidator.validate(cpnet)
  end

  test "invalid: place references an unknown colour set", %{cpnet: cpnet} do
    cpnet = %{
      cpnet
      | places: [
          %Place{name: "p1", colour_set: :int},
          %Place{name: "p2", colour_set: :ghost}
        ]
    }

    assert {:error, %MissingColourSetError{colour_set: :ghost} = error} =
             PlacesValidator.validate(cpnet)

    assert Exception.message(error) =~ "p2"
    assert Exception.message(error) =~ "ghost"
  end
end
