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
            %Marking{place: "input", tokens: ~MS[1]}
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
            %Marking{place: "input", tokens: ~MS[1]}
          ]
        }
      }

      [workitem_1: workitem_1, workitem_2: workitem_2]
    end

    test "works", %{workitem_1: workitem_1, workitem_2: workitem_2} do
      assert {:ok, allocated_workitems, remaning_workitems} =
               WorkitemConsumption.pop_workitems(
                 to_map([workitem_1, workitem_2]),
                 [workitem_1.id],
                 :enabled
               )

      assert %{workitem_1.id => workitem_1} === allocated_workitems
      assert %{workitem_2.id => workitem_2} === remaning_workitems
    end

    test "returns workitem_not_found error", %{workitem_1: workitem_1, workitem_2: workitem_2} do
      workitem_id = Ecto.UUID.generate()

      assert {:error, {:workitem_not_found, workitem_id}} ===
               WorkitemConsumption.pop_workitems(
                 to_map([workitem_1, workitem_2]),
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
                 to_map([workitem_1, workitem_2]),
                 [workitem_2.id],
                 :enabled
               )
    end
  end

  describe "consume_tokens" do
    test "works" do
      place_markings = [
        %Marking{place: "a", tokens: ~MS[1]},
        %Marking{place: "b", tokens: ~MS[1]},
        %Marking{place: "c", tokens: ~MS[1]}
      ]

      binding_element_1 = %BindingElement{
        transition: "t",
        binding: [],
        to_consume: [
          %Marking{place: "a", tokens: ~MS[1]},
          %Marking{place: "b", tokens: ~MS[1]}
        ]
      }

      binding_element_2 = %BindingElement{
        transition: "t",
        binding: [],
        to_consume: [
          %Marking{place: "c", tokens: ~MS[1]}
        ]
      }

      assert {:ok, %{}} ===
               WorkitemConsumption.consume_tokens(to_map(place_markings), [
                 binding_element_1,
                 binding_element_2
               ])

      assert {:ok, %{"c" => %Marking{place: "c", tokens: ~MS[1]}}} ===
               WorkitemConsumption.consume_tokens(to_map(place_markings), [
                 binding_element_1
               ])
    end

    test "tokens are consumed partially" do
      place_markings = [
        %Marking{place: "a", tokens: ~MS[2**1]}
      ]

      binding_element = %BindingElement{
        transition: "t",
        binding: [],
        to_consume: [
          %Marking{place: "a", tokens: ~MS[1]}
        ]
      }

      assert {:ok, %{"a" => %Marking{place: "a", tokens: ~MS[1]}}} ===
               WorkitemConsumption.consume_tokens(to_map(place_markings), [binding_element])
    end

    test "empty markings or binding_elements" do
      place_markings =
        to_map([
          %Marking{place: "a", tokens: ~MS[1]},
          %Marking{place: "b", tokens: ~MS[1]},
          %Marking{place: "c", tokens: ~MS[1]}
        ])

      to_consume = [
        %Marking{place: "a", tokens: ~MS[1]},
        %Marking{place: "b", tokens: ~MS[1]}
      ]

      binding_element = %BindingElement{
        transition: "t",
        binding: [],
        to_consume: to_consume
      }

      assert {:ok, place_markings} === WorkitemConsumption.consume_tokens(place_markings, [])

      assert {:error, {:unsufficient_tokens, to_consume}} ===
               WorkitemConsumption.consume_tokens(%{}, [binding_element])
    end

    test "returns unsufficient_tokens error" do
      place_markings = [
        %Marking{place: "a", tokens: ~MS[1]},
        %Marking{place: "b", tokens: ~MS[1]},
        %Marking{place: "c", tokens: ~MS[1]}
      ]

      binding_elements = [
        %BindingElement{
          transition: "t",
          binding: [],
          to_consume: [
            %Marking{place: "a", tokens: ~MS[1]},
            %Marking{place: "b", tokens: ~MS[1]}
          ]
        },
        %BindingElement{
          transition: "t",
          binding: [],
          to_consume: [
            %Marking{place: "c", tokens: ~MS[2]}
          ]
        }
      ]

      assert {
               :error,
               {
                 :unsufficient_tokens,
                 %Marking{place: "c", tokens: ~MS[1]}
               }
             } === WorkitemConsumption.consume_tokens(to_map(place_markings), binding_elements)
    end

    test "raises error when place marking is absent" do
      place_markings = [
        %Marking{place: "a", tokens: ~MS[1]},
        %Marking{place: "b", tokens: ~MS[1]},
        %Marking{place: "c", tokens: ~MS[1]}
      ]

      binding_elements = [
        %BindingElement{
          transition: "t",
          binding: [],
          to_consume: [
            %Marking{place: "d", tokens: ~MS[2]}
          ]
        }
      ]

      assert_raise RuntimeError, ~r/making is absent/, fn ->
        WorkitemConsumption.consume_tokens(to_map(place_markings), binding_elements)
      end
    end
  end

  defp to_map([]), do: %{}

  defp to_map([%Enactment.Workitem{} | _rest] = workitems) do
    Map.new(workitems, &{&1.id, &1})
  end

  defp to_map([%Marking{} | _rest] = markings) do
    Map.new(markings, &{&1.place, &1})
  end
end
