defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.MarkingTest do
  use ColouredFlow.Runner.CodecCase, codec: Marking, async: true

  alias ColouredFlow.Enactment.Marking

  import ColouredFlow.MultiSet

  describe "codec" do
    test "works" do
      list = [
        %Marking{place: "p1", tokens: ~MS[1]},
        %Marking{place: "p1", tokens: ~MS[1**2 2**3]}
      ]

      assert_codec(list)
    end
  end
end
