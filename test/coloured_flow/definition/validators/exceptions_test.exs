defmodule ColouredFlow.Definition.Validators.ExceptionsTest do
  use ExUnit.Case, async: true
  alias ColouredFlow.Definition.Validators.Exceptions

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
end
