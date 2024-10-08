defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.TransitionTest do
  use ColouredFlow.Runner.CodecCase, codec: Transition, async: true

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Transition

  describe "codec" do
    test "works" do
      code = Expression.build!("{1, x}")

      complex_code =
        Expression.build!("""
        quotient = div(dividend, divisor)
        modulo = Integer.mod(dividend, divisor)

        {quotient, modulo}
        """)

      list = [
        %Transition{
          name: "t1",
          guard: Expression.build!("x > 0"),
          action: %Action{code: code, outputs: [:x]}
        },
        %Transition{
          name: "t2",
          guard: Expression.build!("divisor != 0"),
          action: %Action{code: complex_code, outputs: [:quotient, :modulo]}
        }
      ]

      assert_codec(list)
    end
  end
end
