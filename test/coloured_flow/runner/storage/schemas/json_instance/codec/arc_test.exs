defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.ArcTest do
  use ColouredFlow.Runner.CodecCase, codec: Arc, async: true

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.Expression

  describe "codec" do
    test "works" do
      simple_expression = Expression.build!("bind {1, 2}")

      expression =
        Expression.build!("""
        # this is multiple line code
        if x > 0 do
          bind {x, 1}
        else
          bind {0, 1}
        end
        """)

      list = [
        %Arc{
          label: "pass_through",
          orientation: :p_to_t,
          transition: "t1",
          place: "p1",
          expression: simple_expression,
          bindings: Arc.build_bindings!(simple_expression)
        },
        %Arc{
          label: "comparison",
          orientation: :p_to_t,
          transition: "t1",
          place: "p1",
          expression: expression,
          bindings: Arc.build_bindings!(expression)
        }
      ]

      assert_codec(list)
    end
  end
end
