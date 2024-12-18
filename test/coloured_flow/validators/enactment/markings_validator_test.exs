defmodule ColouredFlow.Validators.Enactment.MarkingsValidatorTest do
  use ExUnit.Case, async: true

  import ColouredFlow.MultiSet
  import ColouredFlow.Notation.Colset

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Validators.Enactment.MarkingsValidator
  alias ColouredFlow.Validators.Exceptions.InvalidMarkingError

  describe "validate/2" do
    setup do
      cpnet = %ColouredPetriNet{
        colour_sets: [colset(int :: integer())],
        places: [%Place{name: "input", colour_set: :int}],
        transitions: [],
        arcs: [],
        variables: []
      }

      [cpnet: cpnet]
    end

    test "works", %{cpnet: cpnet} do
      assert {:ok, _marking} =
               MarkingsValidator.validate(
                 [
                   %Marking{place: "input", tokens: ~MS[]},
                   %Marking{place: "input", tokens: ~MS[1]},
                   %Marking{place: "input", tokens: ~MS[2**1 2]}
                 ],
                 cpnet
               )
    end

    test "InvalidMarkingError", %{cpnet: cpnet} do
      assert {:error, %InvalidMarkingError{reason: :missing_place}} =
               MarkingsValidator.validate([%Marking{place: "output", tokens: ~MS[1]}], cpnet)
    end

    test "ColourSetMismatch", %{cpnet: cpnet} do
      assert {:error, %InvalidMarkingError{reason: :invalid_tokens}} =
               MarkingsValidator.validate(
                 [%Marking{place: "input", tokens: ~MS[2**1 "2"]}],
                 cpnet
               )
    end
  end
end
