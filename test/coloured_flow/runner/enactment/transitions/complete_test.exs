defmodule ColouredFlow.Runner.Enactment.Transitions.CompleteTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Occurrence

  alias ColouredFlow.Runner.Exceptions
  alias ColouredFlow.Runner.Storage

  describe "complete workitems" do
    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    @describetag cpnet: :simple_sequence
    @describetag initial_markings: [%Marking{place: "input", tokens: ~MS[3**1]}]

    setup %{enactment_server: enactment_server} do
      [
        %Enactment.Workitem{state: :enabled} = workitem_1,
        %Enactment.Workitem{state: :enabled} = workitem_2,
        %Enactment.Workitem{state: :enabled} = workitem_3
      ] = get_enactment_workitems(enactment_server)

      workitem_2 = allocate_workitem(workitem_2, enactment_server)
      workitem_3 = start_workitem(workitem_3, enactment_server)

      [
        enabled_workitem: workitem_1,
        allocated_workitem: workitem_2,
        started_workitem: workitem_3
      ]
    end

    test "works", %{
      enactment_server: enactment_server,
      enabled_workitem: enabled_workitem,
      allocated_workitem: allocated_workitem,
      started_workitem: started_workitem
    } do
      {:ok, [completed_workitem]} =
        GenServer.call(enactment_server, {:complete_workitems, %{started_workitem.id => []}})

      assert :completed === completed_workitem.state

      assert [allocated_workitem, enabled_workitem] ===
               enactment_server |> get_enactment_workitems() |> Enum.sort_by(& &1.state)

      assert [allocated_workitem, completed_workitem, enabled_workitem] ===
               Schemas.Workitem
               |> Repo.all()
               |> Enum.map(&Schemas.Workitem.to_workitem/1)
               |> Enum.sort_by(& &1.state)
    end

    test "persists occurrences", %{
      enactment_server: enactment_server,
      enactment: enactment,
      started_workitem: started_workitem
    } do
      {:ok, [completed_workitem]} =
        GenServer.call(enactment_server, {:complete_workitems, %{started_workitem.id => []}})

      assert :completed === completed_workitem.state

      enactment_state = get_enactment_state(enactment_server)

      stop_supervised!(enactment.id)

      [enactment_server: new_genactment_server] = start_enactment(%{enactment: enactment})

      assert enactment_state === get_enactment_state(new_genactment_server)

      assert [
               %Occurrence{
                 binding_element: %BindingElement{
                   transition: "pass_through",
                   binding: [x: 1],
                   to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
                 },
                 free_binding: [],
                 to_produce: [%Marking{place: "output", tokens: ~MS[1]}]
               }
             ] ===
               Schemas.Occurrence
               |> Repo.all()
               |> Enum.map(&Schemas.Occurrence.to_occurrence/1)
    end

    test "returns InvalidWorkitemTransition exception", %{
      enactment: enactment,
      enactment_server: enactment_server,
      allocated_workitem: allocated_workitem
    } do
      assert {:error, exception} =
               GenServer.call(
                 enactment_server,
                 {:complete_workitems, %{allocated_workitem.id => []}}
               )

      assert %Exceptions.InvalidWorkitemTransition{
               id: allocated_workitem.id,
               enactment_id: enactment.id,
               state: :allocated,
               transition: :complete
             } === exception
    end

    test "returns NonLiveWorkitem exception", %{
      enactment: enactment,
      enactment_server: enactment_server
    } do
      workitem_id = Ecto.UUID.generate()

      assert {:error, exception} =
               GenServer.call(enactment_server, {:complete_workitems, %{workitem_id => []}})

      assert %Exceptions.NonLiveWorkitem{
               id: workitem_id,
               enactment_id: enactment.id
             } === exception
    end
  end

  describe "persists occurrences sequentially" do
    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    @tag cpnet: :deferred_choice
    @tag initial_markings: [
           %Marking{place: "input", tokens: ~MS[1]},
           %Marking{place: "place", tokens: ~MS[1]}
         ]
    test "works", %{enactment_server: enactment_server} do
      [
        %Enactment.Workitem{
          binding_element: %BindingElement{transition: "deferred_choice_1"}
        } = dc1_workitem,
        %Enactment.Workitem{
          binding_element: %BindingElement{transition: "deferred_choice_2"}
        } = dc2_workitem,
        %Enactment.Workitem{
          binding_element: %BindingElement{transition: "pass_through"}
        } = pt_workitem
      ] = get_enactment_workitems(enactment_server)

      dc1_workitem = start_workitem(dc1_workitem, enactment_server)
      pt_workitem = start_workitem(pt_workitem, enactment_server)

      assert {:ok, completed_workitems} =
               GenServer.call(
                 enactment_server,
                 {:complete_workitems, %{dc1_workitem.id => [], pt_workitem.id => []}}
               )

      assert Enum.sort([
               %Enactment.Workitem{dc1_workitem | state: :completed},
               %Enactment.Workitem{pt_workitem | state: :completed}
             ]) === Enum.sort(completed_workitems)

      assert %{version: 2} = get_enactment_state(enactment_server)

      assert :withdrawn === Repo.get(Schemas.Workitem, dc2_workitem.id).state

      occurrence_steps = Schemas.Occurrence |> Repo.all() |> Enum.map(& &1.step_number)

      assert [1, 2] === occurrence_steps
    end
  end

  describe "tokens changed" do
    setup :setup_cpnet
    setup :update_out_arc_expression
    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    @tag cpnet: :simple_sequence
    @tag out_arc_expression: ~S[{2, x}]
    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[2**1]}]
    test "consumes and produces tokens", %{enactment_server: enactment_server} do
      previous_markings = get_enactment_markings(enactment_server)

      workitem =
        enactment_server |> get_enactment_workitems() |> hd() |> start_workitem(enactment_server)

      {:ok, [completed_workitem]} =
        GenServer.call(enactment_server, {:complete_workitems, %{workitem.id => []}})

      assert :completed === completed_workitem.state

      markings = get_enactment_markings(enactment_server)

      assert [%Marking{place: "input", tokens: ~MS[2**1]}] === previous_markings

      assert [
               %Marking{place: "input", tokens: ~MS[1]},
               %Marking{place: "output", tokens: ~MS[2**1]}
             ] === markings
    end
  end

  describe "returns errors on occur" do
    setup :setup_cpnet
    setup :update_out_arc_expression
    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    @describetag cpnet: :simple_sequence

    @tag out_arc_expression: ~S[raise ArgumentError, "Bad out arc"]
    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "returns user raised exception", %{enactment_server: enactment_server} do
      [workitem] = get_enactment_workitems(enactment_server)
      workitem = start_workitem(workitem, enactment_server)

      assert {:error, exception} =
               GenServer.call(enactment_server, {:complete_workitems, %{workitem.id => []}})

      assert %ArgumentError{message: "Bad out arc"} = exception
    end

    @tag out_arc_expression: ~S[{1, a + b}]
    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "returns EvalDiagnostic", %{enactment_server: enactment_server} do
      [workitem] = get_enactment_workitems(enactment_server)
      workitem = start_workitem(workitem, enactment_server)

      assert {:error, exception} =
               GenServer.call(enactment_server, {:complete_workitems, %{workitem.id => []}})

      assert %ColouredFlow.Expression.EvalDiagnostic{
               message: ~S[undefined variable "a"]
             } = exception
    end

    @tag out_arc_expression: ~S[{x, "hello"}]
    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "returns ColourSetMismatch", %{enactment_server: enactment_server} do
      [workitem] = get_enactment_workitems(enactment_server)
      workitem = start_workitem(workitem, enactment_server)

      assert {:error, exception} =
               GenServer.call(enactment_server, {:complete_workitems, %{workitem.id => []}})

      assert %ColouredFlow.Definition.ColourSet.ColourSetMismatch{
               colour_set: %ColouredFlow.Definition.ColourSet{name: :int, type: {:integer, []}},
               value: "hello"
             } = exception
    end
  end

  describe "with outputs" do
    setup do
      import ColouredFlow.Notation.Colset

      use ColouredFlow.DefinitionHelpers

      cpnet =
        %ColouredPetriNet{
          colour_sets: [
            colset(int() :: integer())
          ],
          places: [
            %Place{name: "input", colour_set: :int},
            %Place{name: "output", colour_set: :int}
          ],
          transitions: [
            build_transition!(
              name: "pass_through",
              action: [
                payload: "{1 + x}",
                inputs: [:x],
                outputs: [:y]
              ]
            )
          ],
          arcs: [
            build_arc!(
              label: "in",
              place: "input",
              transition: "pass_through",
              orientation: :p_to_t,
              expression: "bind {1, x}"
            ),
            build_arc!(
              label: "out",
              place: "output",
              transition: "pass_through",
              orientation: :t_to_p,
              expression: "{y, x}"
            )
          ],
          variables: [
            %Variable{name: :x, colour_set: :int},
            %Variable{name: :y, colour_set: :int}
          ]
        }

      [cpnet: cpnet]
    end

    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[2**1]}]
    test "works", %{enactment_server: enactment_server} do
      workitem = enactment_server |> get_enactment_workitems() |> hd()
      workitem = start_workitem(workitem, enactment_server)
      outputs = [y: 2]

      assert {:ok, [completed_workitem]} =
               GenServer.call(enactment_server, {:complete_workitems, %{workitem.id => outputs}})

      assert %{workitem | state: :completed} === completed_workitem

      assert [
               %Occurrence{
                 binding_element: %BindingElement{
                   transition: "pass_through",
                   binding: [x: 1],
                   to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
                 },
                 free_binding: [y: 2],
                 to_produce: [%Marking{place: "output", tokens: ~MS[2**1]}]
               }
             ] ===
               Schemas.Occurrence
               |> Repo.all()
               |> Enum.map(&Schemas.Occurrence.to_occurrence/1)

      assert [
               %Marking{place: "input", tokens: ~MS[1]},
               %Marking{place: "output", tokens: ~MS[2**1]}
             ] === get_enactment_markings(enactment_server)
    end

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "returns UnboundActionOutput", %{enactment_server: enactment_server} do
      [workitem] = get_enactment_workitems(enactment_server)
      workitem = start_workitem(workitem, enactment_server)
      outputs = []

      assert {:error, exception} =
               GenServer.call(enactment_server, {:complete_workitems, %{workitem.id => outputs}})

      assert %Exceptions.UnboundActionOutput{
               transition: "pass_through",
               output: :y
             } = exception
    end

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "returns ColourSetMismatch", %{enactment_server: enactment_server} do
      alias ColouredFlow.Definition.ColourSet

      [workitem] = get_enactment_workitems(enactment_server)
      workitem = start_workitem(workitem, enactment_server)
      outputs = [y: "foo"]

      assert {:error, exception} =
               GenServer.call(enactment_server, {:complete_workitems, %{workitem.id => outputs}})

      assert %ColourSet.ColourSetMismatch{
               colour_set: %ColourSet{name: :int, type: {:integer, []}},
               value: "foo"
             } = exception
    end
  end

  describe "calibrate workitems" do
    setup do
      cpnet =
        :deferred_choice
        |> ColouredFlow.CpnetBuilder.build_cpnet()
        |> ColouredFlow.CpnetBuilder.update_arc!(
          {:p_to_t, "deferred_choice_2", "place"},
          expression: "bind {2,x}"
        )

      [cpnet: cpnet]
    end

    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    @tag initial_markings: [
           %Marking{place: "input", tokens: ~MS[1]},
           %Marking{place: "place", tokens: ~MS[1]}
         ]
    test "produces new workitems", %{enactment_server: enactment_server} do
      [
        %Enactment.Workitem{
          binding_element: %BindingElement{transition: "deferred_choice_1"}
        } = dc1_workitem,
        %Enactment.Workitem{
          binding_element: %BindingElement{transition: "pass_through"}
        } = pt_workitem
      ] = get_enactment_workitems(enactment_server)

      pt_workitem = start_workitem(pt_workitem, enactment_server)

      assert {:ok, [completed_workitem]} =
               GenServer.call(enactment_server, {:complete_workitems, %{pt_workitem.id => []}})

      assert %Enactment.Workitem{pt_workitem | state: :completed} === completed_workitem

      assert match?(
               [
                 %Enactment.Workitem{
                   state: :enabled,
                   binding_element: %BindingElement{transition: "deferred_choice_1"}
                 } = dc_workitem_1,
                 %Enactment.Workitem{
                   state: :enabled,
                   binding_element: %BindingElement{transition: "deferred_choice_1"}
                 } = dc_workitem_2,
                 %Enactment.Workitem{
                   state: :enabled,
                   binding_element: %BindingElement{transition: "deferred_choice_2"}
                 }
               ]
               when dc1_workitem in [dc_workitem_1, dc_workitem_2],
               get_enactment_workitems(enactment_server)
             )
    end

    @tag initial_markings: [
           %Marking{place: "input", tokens: ~MS[1]},
           %Marking{place: "place", tokens: ~MS[1]}
         ]
    test "produces new workitems when there is non-enabled workitems", %{
      enactment_server: enactment_server
    } do
      [
        %Enactment.Workitem{
          binding_element: %BindingElement{transition: "deferred_choice_1"}
        } = dc1_workitem,
        %Enactment.Workitem{
          binding_element: %BindingElement{transition: "pass_through"}
        } = pt_workitem
      ] = get_enactment_workitems(enactment_server)

      dc1_workitem = allocate_workitem(dc1_workitem, enactment_server)
      pt_workitem = start_workitem(pt_workitem, enactment_server)

      assert {:ok, [completed_workitem]} =
               GenServer.call(enactment_server, {:complete_workitems, %{pt_workitem.id => []}})

      assert %Enactment.Workitem{pt_workitem | state: :completed} === completed_workitem

      assert [
               %Enactment.Workitem{
                 state: :enabled,
                 binding_element: %BindingElement{transition: "deferred_choice_1"}
               },
               ^dc1_workitem
             ] = get_enactment_workitems(enactment_server)
    end
  end

  describe "snapshot" do
    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    @describetag cpnet: :simple_sequence
    @describetag initial_markings: [%Marking{place: "input", tokens: ~MS[2**1]}]

    setup %{enactment_server: enactment_server} do
      %Enactment.Workitem{state: :enabled} =
        workitem =
        enactment_server |> get_enactment_workitems() |> hd

      workitem = start_workitem(workitem, enactment_server)

      [workitem: workitem]
    end

    test "takes after completed", %{
      enactment: enactment,
      initial_markings: initial_markings,
      enactment_server: enactment_server,
      workitem: workitem
    } do
      {:ok, snapshot} = Storage.read_enactment_snapshot(enactment.id)
      assert 0 === snapshot.version
      assert initial_markings === snapshot.markings

      {:ok, [completed_workitem]} =
        GenServer.call(enactment_server, {:complete_workitems, %{workitem.id => []}})

      assert :completed === completed_workitem.state

      # ensure that the snapshot is taken
      get_enactment_state(enactment_server)

      {:ok, new_snapshot} = Storage.read_enactment_snapshot(enactment.id)

      assert 1 === new_snapshot.version

      assert [
               %Marking{place: "input", tokens: ~MS[1]},
               %Marking{place: "output", tokens: ~MS[1]}
             ] === new_snapshot.markings
    end
  end

  defp update_out_arc_expression(%{cpnet: cpnet, out_arc_expression: out_arc_expression}) do
    cpnet =
      Map.update!(cpnet, :arcs, fn [in_arc, out_arc] ->
        out_arc_params =
          out_arc
          |> Map.from_struct()
          |> Map.take([:label, :place, :transition, :orientation])
          |> Map.to_list()
          |> Keyword.put(:expression, out_arc_expression)

        [
          in_arc,
          ColouredFlow.Definition.Helper.build_arc!(out_arc_params)
        ]
      end)

    [cpnet: cpnet]
  end
end
