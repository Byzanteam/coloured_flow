defmodule ColouredFlow.Enactment.Validators.MarkingValidatorTest do
  use ExUnit.Case, async: true

  import ColouredFlow.MultiSet
  import ColouredFlow.Notation.Colset

  alias ColouredFlow.Definition.ColourSet.ColourSetMismatch
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Validators.Exceptions.MissingPlaceError
  alias ColouredFlow.Enactment.Validators.MarkingValidator

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
               MarkingValidator.validate(%Marking{place: "input", tokens: ~MS[]}, cpnet)

      assert {:ok, _marking} =
               MarkingValidator.validate(%Marking{place: "input", tokens: ~MS[1]}, cpnet)

      assert {:ok, _marking} =
               MarkingValidator.validate(%Marking{place: "input", tokens: ~MS[2**1 2]}, cpnet)
    end

    test "MissingPlaceError", %{cpnet: cpnet} do
      assert {:error, %MissingPlaceError{place: "output"}} =
               MarkingValidator.validate(%Marking{place: "output", tokens: ~MS[1]}, cpnet)
    end

    test "ColourSetMismatch", %{cpnet: cpnet} do
      assert {
               :error,
               %ColourSetMismatch{colour_set: :int, value: "2"}
             } = MarkingValidator.validate(%Marking{place: "input", tokens: ~MS[2**1 "2"]}, cpnet)
    end
  end
end
