defmodule ColouredFlow.Definition.TerminationCriteria.MarkingsTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.TerminationCriteria.Markings

  test "works" do
    expr =
      Expression.build!("""
        unit = {}
        match?(%{"output" => output_ms} when multi_set_coefficient(output_ms, unit), markings)
      """)

    assert %Markings{expression: expr}
  end
end
