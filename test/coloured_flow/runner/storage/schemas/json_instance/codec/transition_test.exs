defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.TransitionTest do
  use ColouredFlow.Runner.CodecCase, codec: Transition, async: true
  import ColouredFlow.DefinitionHelpers, only: [build_transition!: 1]

  describe "codec" do
    test "works" do
      code = "{1, x}"

      complex_code =
        """
        quotient = div(dividend, divisor)
        modulo = Integer.mod(dividend, divisor)

        {quotient, modulo}
        """

      list = [
        build_transition!(
          name: "t1",
          guard: "x > 0",
          action: [code: code, outputs: [:x]]
        ),
        build_transition!(
          name: "t2",
          guard: "divisor != 0",
          action: [code: complex_code, outputs: [:quotient, :modulo]]
        )
      ]

      assert_codec(list)
    end
  end
end
