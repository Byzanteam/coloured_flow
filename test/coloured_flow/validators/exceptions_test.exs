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

  test "InvalidGuardError" do
    exception =
      Exceptions.InvalidGuardError.exception(
        reason: :unbound_vars,
        message: "invalid"
      )

    assert Exception.message(exception) =~ ~r/unbound_vars/
  end

  test "InvalidArcError" do
    exception =
      Exceptions.InvalidArcError.exception(
        reason: :incoming_unbound_vars,
        message: "invalid"
      )

    assert Exception.message(exception) =~ ~r/incoming_unbound_vars/
  end

  test "InvalidActionError" do
    exception =
      Exceptions.InvalidActionError.exception(
        reason: :output_not_variable,
        message: "invalid"
      )

    assert Exception.message(exception) =~ ~r/output_not_variable/
  end
end
