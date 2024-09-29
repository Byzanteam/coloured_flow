defmodule ColouredFlow.Runner.Enactment.WorkitemConsumptionTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment
  alias ColouredFlow.Runner.Enactment.WorkitemConsumption

  import ColouredFlow.MultiSet

  describe "pop_workitems" do
    setup do
      workitem_1 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      workitem_2 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :allocated,
        binding_element: %BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      [workitem_1: workitem_1, workitem_2: workitem_2]
    end

    test "works", %{workitem_1: workitem_1, workitem_2: workitem_2} do
      assert {:ok, allocated_workitems, remaning_workitems} =
               WorkitemConsumption.pop_workitems(
                 [workitem_1, workitem_2],
                 [workitem_1.id],
                 :enabled
               )

      assert [workitem_1] === allocated_workitems
      assert [workitem_2] === remaning_workitems
    end

    test "returns workitem_not_found error", %{workitem_1: workitem_1, workitem_2: workitem_2} do
      workitem_id = Ecto.UUID.generate()

      assert {:error, {:workitem_not_found, workitem_id}} ===
               WorkitemConsumption.pop_workitems(
                 [workitem_1, workitem_2],
                 [workitem_id],
                 :enabled
               )
    end

    test "returns workitem_unexpected_state error", %{
      workitem_1: workitem_1,
      workitem_2: workitem_2
    } do
      assert {:error, {:workitem_unexpected_state, workitem_2}} ===
               WorkitemConsumption.pop_workitems(
                 [workitem_1, workitem_2],
                 [workitem_2.id],
                 :enabled
               )
    end
  end

  describe "consume_tokens" do
    test "works" do
      place_markings = [
        %Marking{place: "a", tokens: ~b[1]},
        %Marking{place: "b", tokens: ~b[1]},
        %Marking{place: "c", tokens: ~b[1]}
      ]

      binding_elements = [
        %BindingElement{
          transition: "t",
          binding: [],
          to_consume: [
            %Marking{place: "a", tokens: ~b[1]},
            %Marking{place: "b", tokens: ~b[1]}
          ]
        },
        %BindingElement{
          transition: "t",
          binding: [],
          to_consume: [
            %Marking{place: "c", tokens: ~b[1]}
          ]
        }
      ]

      assert {:ok, []} === WorkitemConsumption.consume_tokens(place_markings, binding_elements)
    end

    test "returns unsufficient_tokens error" do
      place_markings = [
        %Marking{place: "a", tokens: ~b[1]},
        %Marking{place: "b", tokens: ~b[1]},
        %Marking{place: "c", tokens: ~b[1]}
      ]

      binding_elements = [
        %BindingElement{
          transition: "t",
          binding: [],
          to_consume: [
            %Marking{place: "a", tokens: ~b[1]},
            %Marking{place: "b", tokens: ~b[1]}
          ]
        },
        %BindingElement{
          transition: "t",
          binding: [],
          to_consume: [
            %Marking{place: "c", tokens: ~b[2]}
          ]
        }
      ]

      assert {
               :error,
               {
                 :unsufficient_tokens,
                 %Marking{place: "c", tokens: ~b[1]}
               }
             } === WorkitemConsumption.consume_tokens(place_markings, binding_elements)
    end

    test "raises error when place marking is absent" do
      place_markings = [
        %Marking{place: "a", tokens: ~b[1]},
        %Marking{place: "b", tokens: ~b[1]},
        %Marking{place: "c", tokens: ~b[1]}
      ]

      binding_elements = [
        %BindingElement{
          transition: "t",
          binding: [],
          to_consume: [
            %Marking{place: "d", tokens: ~b[2]}
          ]
        }
      ]

      assert_raise RuntimeError, ~r/are not consumed/, fn ->
        WorkitemConsumption.consume_tokens(place_markings, binding_elements)
      end
    end
  end
end
