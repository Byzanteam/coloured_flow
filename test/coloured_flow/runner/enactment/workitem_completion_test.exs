defmodule ColouredFlow.Runner.Enactment.WorkitemCompletionTest do
  use ExUnit.Case, async: true
  import ColouredFlow.RunnerHelpers, only: :functions
  import ColouredFlow.CpnetBuilder, only: :functions

  alias ColouredFlow.Definition.ColourSet

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence

  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Enactment.WorkitemCompletion

  import ColouredFlow.MultiSet

  describe "complete" do
    setup :setup_cpnet

    @describetag cpnet: :simple_sequence

    test "empty workitem_and_outputs", %{cpnet: cpnet} do
      workitem_and_outputs = []

      assert {:ok, []} === WorkitemCompletion.complete(workitem_and_outputs, cpnet)
    end

    test "completes a single workitem", %{cpnet: cpnet} do
      workitem =
        build_workitem(%BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: [1]}]
        })

      workitem_and_outputs = [{workitem, []}]

      assert {:ok,
              [
                {
                  workitem,
                  %Occurrence{
                    binding_element: workitem.binding_element,
                    free_binding: [],
                    to_produce: [%Marking{place: "output", tokens: ~b[1]}]
                  }
                }
              ]} === WorkitemCompletion.complete(workitem_and_outputs, cpnet)
    end

    test "completes multiple workitems", %{cpnet: cpnet} do
      workitem_1 =
        build_workitem(%BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: [1]}]
        })

      workitem_2 =
        build_workitem(%BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: [1]}]
        })

      workitem_and_outputs = [{workitem_1, []}, {workitem_2, []}]

      assert {:ok,
              [
                {
                  workitem_1,
                  %Occurrence{
                    binding_element: workitem_1.binding_element,
                    free_binding: [],
                    to_produce: [%Marking{place: "output", tokens: ~b[1]}]
                  }
                },
                {
                  workitem_2,
                  %Occurrence{
                    binding_element: workitem_2.binding_element,
                    free_binding: [],
                    to_produce: [%Marking{place: "output", tokens: ~b[1]}]
                  }
                }
              ]} === WorkitemCompletion.complete(workitem_and_outputs, cpnet)
    end

    test "returns occur's errors", %{cpnet: cpnet} do
      cpnet = update_arc!(cpnet, {:t_to_p, "pass_through", "output"}, expression: "{1, x / 0}")

      workitem =
        build_workitem(%BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: [1]}]
        })

      workitem_and_outputs = [{workitem, []}]

      assert {:error, %ArithmeticError{message: "bad argument in arithmetic expression"}} ===
               WorkitemCompletion.complete(workitem_and_outputs, cpnet)
    end
  end

  describe "complete with outputs" do
    setup do
      # ```mermaid
      # flowchart TB
      #   %% colset int() :: integer()
      #
      #   i((input))
      #   o((output))
      #
      #   pt[pass_through]
      #
      #   i --{1,x}--> pt --{1,y}--> o
      # ```
      cpnet =
        :simple_sequence
        |> build_cpnet()
        |> update_transition!("pass_through",
          action: [code: "{x + 1}", inputs: [:x], outputs: [:y]]
        )
        |> update_arc!({:t_to_p, "pass_through", "output"}, expression: "{1,y}")
        |> Map.update!(:variables, fn variables ->
          [%ColouredFlow.Definition.Variable{name: :y, colour_set: :int} | variables]
        end)

      [cpnet: cpnet]
    end

    test "empty workitem_and_outputs", %{cpnet: cpnet} do
      workitem_and_outputs = []

      assert {:ok, []} === WorkitemCompletion.complete(workitem_and_outputs, cpnet)
    end

    test "completes a single workitem", %{cpnet: cpnet} do
      workitem =
        build_workitem(%BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: [1]}]
        })

      workitem_and_outputs = [{workitem, [y: 1]}]

      assert {:ok,
              [
                {
                  workitem,
                  %Occurrence{
                    binding_element: workitem.binding_element,
                    free_binding: [y: 1],
                    to_produce: [%Marking{place: "output", tokens: ~b[1]}]
                  }
                }
              ]} === WorkitemCompletion.complete(workitem_and_outputs, cpnet)
    end

    test "completes multiple workitems", %{cpnet: cpnet} do
      workitem_1 =
        build_workitem(%BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: [1]}]
        })

      workitem_2 =
        build_workitem(%BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: [2]}]
        })

      workitem_and_outputs = [{workitem_1, [y: 2]}, {workitem_2, [y: 3]}]

      assert {:ok,
              [
                {
                  workitem_1,
                  %Occurrence{
                    binding_element: workitem_1.binding_element,
                    free_binding: [y: 2],
                    to_produce: [%Marking{place: "output", tokens: ~b[2]}]
                  }
                },
                {
                  workitem_2,
                  %Occurrence{
                    binding_element: workitem_2.binding_element,
                    free_binding: [y: 3],
                    to_produce: [%Marking{place: "output", tokens: ~b[3]}]
                  }
                }
              ]} === WorkitemCompletion.complete(workitem_and_outputs, cpnet)
    end

    test "returns unbound_action_output", %{cpnet: cpnet} do
      workitem =
        build_workitem(%BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: [1]}]
        })

      workitem_and_outputs = [{workitem, []}]

      assert {:error,
              %ColouredFlow.Runner.Exceptions.UnboundActionOutput{
                transition: "pass_through",
                output: :y
              }} === WorkitemCompletion.complete(workitem_and_outputs, cpnet)
    end

    test "returns colour_set_mismatch", %{cpnet: cpnet} do
      workitem =
        build_workitem(%BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: [1]}]
        })

      workitem_and_outputs = [{workitem, [y: "a"]}]

      assert {:error,
              %ColourSet.ColourSetMismatch{
                colour_set: %ColourSet{name: :int, type: {:integer, []}},
                value: "a"
              }} === WorkitemCompletion.complete(workitem_and_outputs, cpnet)
    end

    test "returns occur's errors", %{cpnet: cpnet} do
      cpnet = update_arc!(cpnet, {:t_to_p, "pass_through", "output"}, expression: "{1,y/0}")

      workitem =
        build_workitem(%BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: [1]}]
        })

      workitem_and_outputs = [{workitem, [y: "a"]}]

      assert {
               :error,
               %ColourSet.ColourSetMismatch{
                 colour_set: %ColourSet{name: :int, type: {:integer, []}},
                 value: "a"
               }
             } === WorkitemCompletion.complete(workitem_and_outputs, cpnet)
    end
  end

  defp build_workitem(binding_element) do
    %Workitem{
      id: Ecto.UUID.generate(),
      state: :started,
      binding_element: binding_element
    }
  end
end
