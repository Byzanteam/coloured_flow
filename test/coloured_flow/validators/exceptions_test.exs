defmodule ColouredFlow.Validators.ExceptionsTest do
  use ExUnit.Case, async: true
  alias ColouredFlow.Validators.Exceptions

  test "UniqueNameViolationError.message/1" do
    exception = Exceptions.UniqueNameViolationError.exception(scope: :place, name: "input")

    assert """
           The name `"input"` is not unique within the place.
           """ === Exception.message(exception)

    exception = Exceptions.UniqueNameViolationError.exception(scope: :colour_set, name: :int)

    assert """
           The name `:int` is not unique within the colour_set.
           """ === Exception.message(exception)
  end

  test "InvalidColourSetError" do
    exception =
      Exceptions.InvalidColourSetError.exception(
        message: "invalid enum item",
        reason: :invalid_enum_item,
        descr: {:enum, [:foo, "bar"]}
      )

    assert Exception.message(exception) =~ "invalid_enum_item"
  end

  test "InvalidMarkingError" do
    exception =
      Exceptions.InvalidMarkingError.exception(reason: :missing_place, message: "invalid")

    assert """
           The marking is invalid, due to :missing_place.
           invalid
           """ === Exception.message(exception)
  end

  test "InvalidStructureError" do
    exception =
      Exceptions.InvalidStructureError.exception(
        message: "invalid",
        reason: :missing_place
      )

    assert Exception.message(exception) =~ ~r/missing_place/
  end
end
