defmodule ColouredFlow.Validators.Definition.InvalidColourSetTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColourSet.Descr
  alias ColouredFlow.Definition.ColouredPetriNet

  alias ColouredFlow.Validators.Definition.ColourSetValidator
  alias ColouredFlow.Validators.Exceptions.InvalidColourSetError

  test "valid" do
    assert {:ok, _cpnet} =
             validate([
               %ColourSet{name: :my_binary, type: Descr.binary()}
             ])

    assert {:ok, _cpnet} =
             validate([
               %ColourSet{
                 name: :sex,
                 type: Descr.enum([:female, :male])
               },
               %ColourSet{
                 name: :user,
                 type:
                   Descr.map(
                     name: Descr.binary(),
                     age: Descr.integer(),
                     enum: Descr.type(:sex)
                   )
               },
               %ColourSet{
                 name: :complex,
                 type:
                   Descr.union(
                     integer: Descr.integer(),
                     unit: Descr.unit(),
                     list: Descr.list(Descr.list(Descr.integer())),
                     tuple: Descr.tuple([Descr.integer(), Descr.integer()]),
                     map: Descr.type(:user)
                   )
               }
             ])
  end

  test "name can't be built_in type names" do
    assert {:error, %InvalidColourSetError{reason: :built_in_type}} =
             validate([
               %ColourSet{name: :binary, type: Descr.binary()}
             ])
  end

  test "invalid_map_key" do
    assert {:error, %InvalidColourSetError{reason: :invalid_map_key}} =
             validate([
               %ColourSet{name: :my_map, type: Descr.map([{"foo", Descr.integer()}])}
             ])
  end

  test "invalid_enum_item" do
    assert {:error, %InvalidColourSetError{reason: :invalid_enum_item}} =
             validate([
               %ColourSet{name: :my_enum, type: Descr.enum([:foo, "bar"])}
             ])
  end

  test "invalid_union_tag" do
    assert {:error, %InvalidColourSetError{reason: :invalid_union_tag}} =
             validate([
               %ColourSet{
                 name: :my_union,
                 type: Descr.union([{"foo", Descr.integer()}, {:bar, Descr.integer()}])
               }
             ])
  end

  test "recursive_type" do
    assert {:error, %InvalidColourSetError{reason: :recursive_type}} =
             validate([
               %ColourSet{
                 name: :node,
                 type: Descr.map(name: Descr.binary(), parent: Descr.type(:node))
               }
             ])

    assert {:error, %InvalidColourSetError{reason: :recursive_type}} =
             validate([
               %ColourSet{name: :a, type: Descr.type(:b)},
               %ColourSet{name: :b, type: Descr.type(:a)}
             ])
  end

  test "undefined_type" do
    assert {:error, %InvalidColourSetError{reason: :undefined_type}} =
             validate([
               %ColourSet{name: :a, type: Descr.type(:b)}
             ])
  end

  test "unsupported_type" do
    assert {:error, %InvalidColourSetError{reason: :unsupported_type}} =
             validate([
               %ColourSet{name: :a, type: {:foo, [Descr.integer()]}}
             ])

    assert {:error, %InvalidColourSetError{reason: :unsupported_type}} =
             validate([
               %ColourSet{name: :a, type: {:binary, [Descr.integer()]}}
             ])
  end

  defp validate(colour_sets) do
    cpnet = %ColouredPetriNet{
      colour_sets: colour_sets,
      places: [],
      transitions: [],
      arcs: [],
      variables: []
    }

    ColourSetValidator.validate(cpnet)
  end
end
