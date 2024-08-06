defmodule ColouredFlow.Definition.ColourSet.ColourSetMismatchTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.ColourSet.ColourSetMismatch

  test "works" do
    colour_set = %ColouredFlow.Definition.ColourSet{name: :int, type: {:integer, []}}
    exception = ColourSetMismatch.exception(colour_set: colour_set, value: true)

    message = Exception.message(exception)

    assert message =~ "colour set:"
    assert message =~ "value:"
  end
end
