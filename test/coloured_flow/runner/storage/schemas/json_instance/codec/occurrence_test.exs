defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.OccurrenceTest do
  use ColouredFlow.Runner.CodecCase, codec: Occurrence, async: true

  import ColouredFlow.MultiSet

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence

  describe "codec" do
    test "works" do
      list = [
        %Occurrence{
          binding_element: %BindingElement{
            transition: "t1",
            binding: [x: 1],
            to_consume: [%Marking{place: "p1", tokens: ~MS[1]}]
          },
          free_binding: [x: 1],
          to_produce: [
            %Marking{place: "p2", tokens: ~MS[2**1]}
          ]
        }
      ]

      assert_codec(list)
    end
  end
end
