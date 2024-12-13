defmodule ColouredFlow.Enactment.Validators.MarkingsValidatorTest do
  use ExUnit.Case, async: true

  import ColouredFlow.MultiSet
  import ColouredFlow.Notation.Colset

  alias ColouredFlow.Definition.ColourSet.ColourSetMismatch
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Validators.Exceptions.MissingPlaceError
  alias ColouredFlow.Enactment.Validators.MarkingsValidator

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

    test "MissingPlaceError", %{cpnet: cpnet} do
      assert {:error, %MissingPlaceError{place: "output"}} =
               MarkingsValidator.validate([%Marking{place: "output", tokens: ~MS[1]}], cpnet)
    end

    test "ColourSetMismatch", %{cpnet: cpnet} do
      assert {
               :error,
               %ColourSetMismatch{colour_set: :int, value: "2"}
             } =
               MarkingsValidator.validate(
                 [%Marking{place: "input", tokens: ~MS[2**1 "2"]}],
                 cpnet
               )
    end
  end
end
