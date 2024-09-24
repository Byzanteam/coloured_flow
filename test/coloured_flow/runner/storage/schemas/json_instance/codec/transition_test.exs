defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.TransitionTest do
  use ColouredFlow.Runner.CodecCase, codec: Transition, async: true

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Transition

  describe "codec" do
    test "works" do
      code = Expression.build!("output {1, x}")
      outputs = Action.build_outputs!(code)

      complex_code =
        Expression.build!("""
        quotient = div(dividend, divisor)
        modulo = Integer.mod(dividend, divisor)

        output {quotient, modulo}
        """)

      complex_outputs = Action.build_outputs!(complex_code)

      list = [
        %Transition{
          name: "t1",
          guard: Expression.build!("x > 0"),
          action: %Action{code: code, outputs: outputs}
        },
        %Transition{
          name: "t2",
          guard: Expression.build!("divisor != 0"),
          action: %Action{code: complex_code, outputs: complex_outputs}
        }
      ]

      assert_codec(list)
    end
  end
end
