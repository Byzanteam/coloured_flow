defmodule ColouredFlow.Runner.TerminationTest do
  use ExUnit.Case, async: true

  import ColouredFlow.MultiSet, only: :sigils

  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.TerminationCriteria.Markings
  alias ColouredFlow.Expression.InvalidResult

  alias ColouredFlow.Runner.Termination

  describe "should_terminate/2" do
    test "works" do
      criteria =
        build_markings_criteria("""
        unit = {}

        match?(%{"output" => output_ms} when multi_set_coefficient(output_ms, unit) > 0, markings)
        """)

      assert {:ok, false} = Termination.should_terminate(criteria, %{})
      assert {:ok, false} = Termination.should_terminate(criteria, %{"output" => ~MS[]})
      assert {:ok, true} = Termination.should_terminate(criteria, %{"output" => ~MS[{}]})
    end

    test "return false when expression is nil" do
      assert {:ok, false} = Termination.should_terminate(%Markings{}, %{})
    end

    test "invalid result" do
      markings = %{}

      criteria =
        build_markings_criteria("""
        "true"
        """)

      assert {:error, [exception]} = Termination.should_terminate(criteria, markings)
      assert is_exception(exception, InvalidResult)
      assert InvalidResult.message(exception) =~ "The expression should return a boolean value"
    end

    test "errors raised" do
      markings = %{}

      criteria =
        build_markings_criteria("""
        raise "error"
        """)

      assert {:error, [exception]} = Termination.should_terminate(criteria, markings)
      assert is_exception(exception, RuntimeError)
    end
  end

  defp build_markings_criteria(expression) do
    %Markings{
      expression: Expression.build!(expression)
    }
  end
end
