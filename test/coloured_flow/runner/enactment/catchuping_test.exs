defmodule ColouredFlow.Runner.Enactment.CatchupingTest do
  use ExUnit.Case

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.Runner.Enactment.Catchuping

  import ColouredFlow.MultiSet

  describe "apply/2" do
    test "works" do
      current_markings = []
      occurrences = []

      assert {0, []} === Catchuping.apply(current_markings, occurrences)
    end

    test "works with consumed and produced tokens" do
      current_markings = [
        %Marking{place: "a", tokens: ~MS[3**:a 4**:b]}
      ]

      occurrence1 = %Occurrence{
        binding_element: %BindingElement{
          transition: "t",
          binding: [x: "a"],
          to_consume: [
            %Marking{place: "a", tokens: ~MS[2**:a]}
          ]
        },
        free_binding: [],
        to_produce: [%Marking{place: "b", tokens: ~MS[2**:b 1**:c]}]
      }

      assert {
               1,
               [
                 %Marking{place: "a", tokens: ~MS[1**:a 4**:b]},
                 %Marking{place: "b", tokens: ~MS[2**:b 1**:c]}
               ]
             } ===
               order(Catchuping.apply(current_markings, [occurrence1]))

      occurrence2 = %Occurrence{
        binding_element: %BindingElement{
          transition: "t",
          binding: [x: "a"],
          to_consume: [
            %Marking{place: "a", tokens: ~MS[1**:a 4**:b]},
            %Marking{place: "b", tokens: ~MS[2**:b 1**:c]}
          ]
        },
        free_binding: [],
        to_produce: [%Marking{place: "c", tokens: ~MS[1**:c]}]
      }

      assert {
               2,
               [%Marking{place: "c", tokens: ~MS[1**:c]}]
             } ===
               order(Catchuping.apply(current_markings, [occurrence1, occurrence2]))
    end
  end

  defp order({steps, markings}) do
    {steps, Enum.sort_by(markings, & &1.place)}
  end
end
