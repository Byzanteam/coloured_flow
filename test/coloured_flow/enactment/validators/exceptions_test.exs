defmodule ColouredFlow.Enactment.Validators.ExceptionsTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Enactment.Validators.Exceptions

  test "MissingPlaceError" do
    exception = Exceptions.MissingPlaceError.exception(place: "input")

    assert """
           The place with name input not found in the coloured petri net.
           """ === Exception.message(exception)
  end
end
