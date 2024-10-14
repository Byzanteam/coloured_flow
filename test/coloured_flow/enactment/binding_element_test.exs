defmodule ColouredFlow.Enactment.BindingElementTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking

  import ColouredFlow.MultiSet

  describe "new" do
    test "build an order-consistent one" do
      transition = "pass_through"

      one =
        BindingElement.new(
          transition,
          [x: 1, y: 2, z: 3],
          [
            %Marking{place: "input", tokens: ~MS[3**1]},
            %Marking{place: "output", tokens: ~MS[2**2]}
          ]
        )

      another =
        BindingElement.new(
          transition,
          [y: 2, x: 1, z: 3],
          [
            %Marking{place: "output", tokens: ~MS[2**2]},
            %Marking{place: "input", tokens: ~MS[3**1]}
          ]
        )

      assert one === another
    end
  end
end
