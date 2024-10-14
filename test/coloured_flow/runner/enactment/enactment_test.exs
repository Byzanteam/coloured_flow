defmodule ColouredFlow.Runner.EnactmentTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Occurrence

  import Ecto.Query

  @moduletag cpnet: :simple_sequence
  @moduletag initial_markings: [%Marking{place: "input", tokens: ~MS[2**1]}]

  setup :setup_flow
  setup :setup_enactment

  describe "populate state" do
    test "without snapshot", %{enactment: enactment} do
      enactment_id = enactment.id

      workitems_query = Schemas.Workitem |> from() |> where(state: :enabled)

      workitems_count = Repo.aggregate(workitems_query, :count)

      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})

      assert %Enactment{
               enactment_id: ^enactment_id,
               version: 0
             } = get_enactment_state(enactment_server)

      assert [%Marking{place: "input", tokens: ~MS[2**1]}] ===
               get_enactment_markings(enactment_server)

      assert match?(
               [
                 %Enactment.Workitem{
                   id: one_workitem_id,
                   state: :enabled,
                   binding_element: %BindingElement{
                     transition: "pass_through",
                     binding: [x: 1],
                     to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
                   }
                 },
                 %Enactment.Workitem{
                   id: two_workitem_id,
                   state: :enabled,
                   binding_element: %BindingElement{
                     transition: "pass_through",
                     binding: [x: 1],
                     to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
                   }
                 }
               ]
               when one_workitem_id != two_workitem_id,
               get_enactment_workitems(enactment_server)
             )

      # Ensure that the workitems are produced
      assert_in_delta workitems_count, Repo.aggregate(workitems_query, :count), 2

      # Ensure that the snapshot is taken
      assert %{version: 0} =
               Schemas.Snapshot |> from() |> where(enactment_id: ^enactment_id) |> Repo.one()
    end

    test "with snapshot", %{enactment: enactment} do
      markings = [
        %Marking{place: "input", tokens: ~MS[1]},
        %Marking{place: "output", tokens: ~MS[1]}
      ]

      :snapshot
      |> build(enactment: enactment, version: 2)
      |> snapshot_with_markings(markings)
      |> insert()

      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})

      assert [
               %Marking{place: "input", tokens: ~MS[1]},
               %Marking{place: "output", tokens: ~MS[1]}
             ] === get_enactment_markings(enactment_server)

      assert [
               %Enactment.Workitem{
                 id: _workitem_id,
                 state: :enabled,
                 binding_element: %BindingElement{
                   transition: "pass_through",
                   binding: [x: 1],
                   to_consume: [
                     %Marking{place: "input", tokens: ~MS[1]}
                   ]
                 }
               }
             ] = get_enactment_workitems(enactment_server)
    end

    test "catchup", %{enactment: enactment} do
      enactment_id = enactment.id
      workitem = :workitem |> build(enactment: enactment, state: :completed) |> insert()

      :occurrence
      |> build(enactment: enactment, workitem: workitem, step_number: 1)
      |> occurrence_with_occurrence(%Occurrence{
        binding_element:
          BindingElement.new(
            "pass_through",
            [x: 1],
            [%Marking{place: "input", tokens: ~MS[1]}]
          ),
        free_binding: [],
        to_produce: [%Marking{place: "output", tokens: ~MS[1]}]
      })
      |> insert()

      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})

      assert [
               %Marking{place: "input", tokens: ~MS[1]},
               %Marking{place: "output", tokens: ~MS[1]}
             ] === get_enactment_markings(enactment_server)

      assert [
               %Enactment.Workitem{
                 id: _workitem_id,
                 state: :enabled,
                 binding_element: %BindingElement{
                   transition: "pass_through",
                   binding: [x: 1],
                   to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
                 }
               }
             ] = get_enactment_workitems(enactment_server)

      # Ensure that the snapshot is taken
      assert %{version: 1} =
               Schemas.Snapshot |> from() |> where(enactment_id: ^enactment_id) |> Repo.one()
    end
  end

  describe "calibrate workitems" do
    test "works", %{enactment: enactment} do
      offered_workitem =
        :workitem
        |> build(enactment: enactment, state: :enabled)
        |> workitem_with_binding_element(
          BindingElement.new(
            "pass_through",
            [x: 2],
            # there isn't a token `2` in the input place
            [%Marking{place: "input", tokens: ~MS[2]}]
          )
        )
        |> insert()

      allocated_workitem =
        :workitem
        |> build(enactment: enactment, state: :allocated)
        |> workitem_with_binding_element(
          BindingElement.new(
            "pass_through",
            [x: 1],
            [%Marking{place: "input", tokens: ~MS[1]}]
          )
        )
        |> insert()

      started_workitem =
        :workitem
        |> build(enactment: enactment, state: :started)
        |> workitem_with_binding_element(
          BindingElement.new(
            "pass_through",
            [x: 2],
            # there isn't a token `2` in the input place
            [%Marking{place: "input", tokens: ~MS[2]}]
          )
        )
        |> insert()

      completed_workitem =
        :workitem
        |> build(enactment: enactment, state: :completed)
        |> workitem_with_binding_element(
          BindingElement.new(
            "pass_through",
            [x: 1],
            [%Marking{place: "input", tokens: ~MS[1]}]
          )
        )
        |> insert()

      withdrawn_workitem =
        :workitem
        |> build(enactment: enactment, state: :withdrawn)
        |> workitem_with_binding_element(
          BindingElement.new(
            "pass_through",
            [x: 1],
            [%Marking{place: "input", tokens: ~MS[1]}]
          )
        )
        |> insert()

      enactment_id = enactment.id

      previous_workitems = Repo.all(Schemas.Workitem)

      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})

      assert %Enactment{
               enactment_id: ^enactment_id,
               version: 0,
               markings: %{"input" => %Marking{place: "input", tokens: ~MS[2**1]}}
             } = get_enactment_state(enactment_server)

      # withdrawn for the binding_element is not satisfied
      assert match?(%{state: :withdrawn}, Repo.reload(offered_workitem))
      assert match?(%{state: :allocated}, Repo.reload(allocated_workitem))
      # withdrawn for the binding_element is not satisfied
      assert match?(%{state: :withdrawn}, Repo.reload(started_workitem))
      assert match?(%{state: :completed}, Repo.reload(completed_workitem))
      assert match?(%{state: :withdrawn}, Repo.reload(withdrawn_workitem))

      allocated_workitem_id = allocated_workitem.id

      assert [
               %Enactment.Workitem{
                 id: produced_workitem_id,
                 state: :enabled,
                 binding_element: %BindingElement{
                   transition: "pass_through",
                   binding: [x: 1],
                   to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
                 }
               },
               %Enactment.Workitem{
                 id: ^allocated_workitem_id,
                 state: :allocated,
                 binding_element: %BindingElement{
                   transition: "pass_through",
                   binding: [x: 1],
                   to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
                 }
               }
             ] = get_enactment_workitems(enactment_server)

      # Ensure that the workitems are produced
      current_workitems = Repo.all(Schemas.Workitem)
      assert_in_delta length(previous_workitems), length(current_workitems), 1

      assert [produced_workitem_id] ===
               Enum.map(current_workitems, & &1.id) -- Enum.map(previous_workitems, & &1.id)
    end
  end
end
