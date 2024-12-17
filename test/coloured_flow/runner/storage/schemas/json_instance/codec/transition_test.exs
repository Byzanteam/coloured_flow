defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.TransitionTest do
  use ColouredFlow.Runner.CodecCase, codec: Transition, async: true
  import ColouredFlow.Builder.DefinitionHelper, only: [build_transition!: 1]

  describe "codec" do
    test "works" do
      payload = "{1, x}"

      complex_payload =
        """
        quotient = div(dividend, divisor)
        modulo = Integer.mod(dividend, divisor)

        {quotient, modulo}
        """

      list = [
        build_transition!(
          name: "t1",
          guard: "x > 0",
          action: [payload: payload, outputs: [:x]]
        ),
        build_transition!(
          name: "t2",
          guard: "divisor != 0",
          action: [payload: complex_payload, outputs: [:quotient, :modulo]]
        )
      ]

      assert_codec(list)
    end
  end
end
