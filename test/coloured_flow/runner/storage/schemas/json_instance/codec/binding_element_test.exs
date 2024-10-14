defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.BindingElementTest do
  use ColouredFlow.Runner.CodecCase, codec: BindingElement, async: true

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking

  import ColouredFlow.MultiSet

  describe "codec" do
    test "works" do
      list = [
        %BindingElement{
          transition: "t1",
          binding: [x: 1],
          to_consume: [%Marking{place: "p1", tokens: ~MS[1]}]
        },
        %BindingElement{
          transition: "t1",
          binding: [x: 1, y: 2],
          to_consume: [%Marking{place: "p1", tokens: ~MS[1**2 2**3]}]
        }
      ]

      assert_codec(list)
    end
  end
end
