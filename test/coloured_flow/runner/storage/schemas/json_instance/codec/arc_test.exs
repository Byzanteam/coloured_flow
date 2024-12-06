defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.ArcTest do
  use ColouredFlow.Runner.CodecCase, codec: Arc, async: true

  alias ColouredFlow.Definition.Arc

  describe "codec" do
    test "works" do
      simple_code = "bind {1, 2}"

      code =
        """
        # this is multiple line code
        if x > 0 do
          bind {x, 1}
        else
          bind {0, 1}
        end
        """

      list = [
        %Arc{
          label: "pass_through",
          orientation: :p_to_t,
          transition: "t1",
          place: "p1",
          expression: Arc.build_expression!(:p_to_t, simple_code)
        },
        %Arc{
          label: "comparison",
          orientation: :p_to_t,
          transition: "t1",
          place: "p1",
          expression: Arc.build_expression!(:p_to_t, code)
        }
      ]

      assert_codec(list)
    end
  end
end
