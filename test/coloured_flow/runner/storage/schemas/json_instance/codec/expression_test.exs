defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.ExpressionTest do
  use ColouredFlow.Runner.CodecCase, codec: Expression, async: true

  alias ColouredFlow.Definition.Expression

  describe "codec" do
    test "works" do
      list = [
        Expression.build!("x + y"),
        Expression.build!("""
        # this is multiple line code
        if x > 0 do
          x + y
        else
          x - y
        end
        """)
      ]

      assert_codec(list)
    end
  end
end
