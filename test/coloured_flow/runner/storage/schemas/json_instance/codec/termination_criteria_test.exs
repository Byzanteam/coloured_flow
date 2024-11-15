defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.TerminationCriteriaTest do
  use ColouredFlow.Runner.CodecCase, codec: TerminationCriteria, async: true

  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.TerminationCriteria

  describe "codec" do
    test "works" do
      code = """
      case markings do
        %{"first" => ms} when multi_set_coefficient(ms, "foo") > 3 ->
          true

        %{"second" => ms} when multi_set_coefficient(ms, 2) > 2 ->
          true

        _markings ->
          false
      end
      """

      criteria =
        %TerminationCriteria{
          markings: %TerminationCriteria.Markings{expression: Expression.build!(code)}
        }

      assert_codec([criteria, %{criteria | markings: nil}])
    end
  end
end
