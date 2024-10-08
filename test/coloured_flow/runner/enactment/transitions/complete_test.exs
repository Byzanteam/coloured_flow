defmodule ColouredFlow.Runner.Enactment.Transitions.CompleteTest do
  use ColouredFlow.RepoCase

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence

  alias ColouredFlow.Runner.Enactment
  alias ColouredFlow.Runner.Exceptions

  import ColouredFlow.MultiSet

  describe "complete workitems" do
    setup do
      flow = :flow |> build() |> flow_with_cpnet(:simple_sequence) |> insert()
      initial_markings = [%Marking{place: "input", tokens: ~b[3**1]}]

      enactment =
        :enactment
        |> build(flow: flow)
        |> enactment_with_initial_markings(initial_markings)
        |> insert()

      pid = start_link_supervised!({Enactment, enactment_id: enactment.id}, id: enactment.id)

      [
        %Enactment.Workitem{state: :enabled} = workitem_1,
        %Enactment.Workitem{state: :enabled} = workitem_2,
        %Enactment.Workitem{state: :enabled} = workitem_3
      ] = get_workitems(pid)

      workitem_2 = allocate_workitem(workitem_2, pid)
      workitem_3 = start_workitem(workitem_3, pid)

      [
        flow: flow,
        enactment: enactment,
        pid: pid,
        enabled_workitem: workitem_1,
        allocated_workitem: workitem_2,
        started_workitem: workitem_3
      ]
    end

    test "works", %{
      pid: pid,
      enabled_workitem: enabled_workitem,
      allocated_workitem: allocated_workitem,
      started_workitem: started_workitem
    } do
      {:ok, [completed_workitem]} =
        GenServer.call(pid, {:complete_workitems, %{started_workitem.id => []}})

      assert :completed === completed_workitem.state

      assert [allocated_workitem, enabled_workitem] ===
               pid |> get_workitems() |> Enum.sort_by(& &1.state)

      assert [allocated_workitem, completed_workitem, enabled_workitem] ===
               Schemas.Workitem
               |> Repo.all()
               |> Enum.map(&Schemas.Workitem.to_workitem/1)
               |> Enum.sort_by(& &1.state)
    end

    test "persists occurrences", %{
      pid: pid,
      enactment: enactment,
      started_workitem: started_workitem
    } do
      {:ok, [completed_workitem]} =
        GenServer.call(pid, {:complete_workitems, %{started_workitem.id => []}})

      assert :completed === completed_workitem.state

      enactment_state = get_enactment_state(pid)

      stop_supervised!(enactment.id)

      new_pid = start_link_supervised!({Enactment, enactment_id: enactment.id}, id: enactment.id)

      assert enactment_state === get_enactment_state(new_pid)

      assert [
               %Occurrence{
                 binding_element: %BindingElement{
                   transition: "pass_through",
                   binding: [x: 1],
                   to_consume: [%Marking{place: "input", tokens: ~b[1]}]
                 },
                 free_binding: [],
                 to_produce: [%Marking{place: "output", tokens: ~b[1]}]
               }
             ] ===
               Schemas.Occurrence
               |> Repo.all()
               |> Enum.map(&Schemas.Occurrence.to_occurrence/1)
    end

    test "returns InvalidWorkitemTransition exception", %{
      enactment: enactment,
      pid: pid,
      allocated_workitem: allocated_workitem
    } do
      assert {:error, exception} =
               GenServer.call(pid, {:complete_workitems, %{allocated_workitem.id => []}})

      assert %Exceptions.InvalidWorkitemTransition{
               id: allocated_workitem.id,
               enactment_id: enactment.id,
               state: :allocated,
               transition: :complete
             } === exception
    end

    test "returns NonLiveWorkitem exception", %{
      enactment: enactment,
      pid: pid
    } do
      workitem_id = Ecto.UUID.generate()

      assert {:error, exception} =
               GenServer.call(pid, {:complete_workitems, %{workitem_id => []}})

      assert %Exceptions.NonLiveWorkitem{
               id: workitem_id,
               enactment_id: enactment.id
             } === exception
    end
  end

  describe "tokens changed" do
    setup :setup_flow
    setup :setup_enactment

    @tag out_arc_expression: ~S[{2, x}]
    @tag initial_markings: [%Marking{place: "input", tokens: ~b[1]}]
    test "consumes and produces tokens", %{pid: pid} do
      previous_markings = get_markings(pid)

      workitem = pid |> get_workitems() |> hd() |> start_workitem(pid)

      {:ok, [completed_workitem]} =
        GenServer.call(pid, {:complete_workitems, %{workitem.id => []}})

      assert :completed === completed_workitem.state

      markings = get_markings(pid)

      assert [%Marking{place: "input", tokens: ~b[1]}] === previous_markings
      assert [%Marking{place: "output", tokens: ~b[2**1]}] === markings
    end
  end

  describe "returns errors on occur" do
    setup :setup_flow
    setup :setup_enactment

    @tag out_arc_expression: ~S[raise ArgumentError, "Bad out arc"]
    @tag initial_markings: [%Marking{place: "input", tokens: ~b[1]}]
    test "returns user raised exception", %{pid: pid} do
      [workitem] = get_workitems(pid)
      workitem = start_workitem(workitem, pid)

      assert {:error, exception} =
               GenServer.call(pid, {:complete_workitems, %{workitem.id => []}})

      assert %ArgumentError{message: "Bad out arc"} = exception
    end

    @tag out_arc_expression: ~S[{1, a + b}]
    @tag initial_markings: [%Marking{place: "input", tokens: ~b[1]}]
    test "returns EvalDiagnostic", %{pid: pid} do
      [workitem] = get_workitems(pid)
      workitem = start_workitem(workitem, pid)

      assert {:error, exception} =
               GenServer.call(pid, {:complete_workitems, %{workitem.id => []}})

      assert %ColouredFlow.Expression.EvalDiagnostic{
               message: ~S[undefined variable "a"]
             } = exception
    end

    @tag out_arc_expression: ~S[{x, "hello"}]
    @tag initial_markings: [%Marking{place: "input", tokens: ~b[1]}]
    test "returns ColourSetMismatch", %{pid: pid} do
      [workitem] = get_workitems(pid)
      workitem = start_workitem(workitem, pid)

      assert {:error, exception} =
               GenServer.call(pid, {:complete_workitems, %{workitem.id => []}})

      assert %ColouredFlow.Definition.ColourSet.ColourSetMismatch{
               colour_set: %ColouredFlow.Definition.ColourSet{name: :int, type: {:integer, []}},
               value: "hello"
             } = exception
    end
  end

  defp get_workitems(pid) do
    pid |> get_enactment_state() |> Map.fetch!(:workitems) |> Map.values()
  end

  defp get_markings(pid) do
    pid |> get_enactment_state() |> Map.fetch!(:markings) |> Map.values()
  end

  defp get_enactment_state(pid) do
    :sys.get_state(pid)
  end

  defp allocate_workitem(%Enactment.Workitem{state: :enabled} = workitem, server)
       when is_pid(server) do
    {:ok, [%Enactment.Workitem{state: :allocated} = workitem]} =
      GenServer.call(server, {:allocate_workitems, [workitem.id]})

    workitem
  end

  defp start_workitem(%Enactment.Workitem{state: :enabled} = workitem, server)
       when is_pid(server) do
    workitem
    |> allocate_workitem(server)
    |> start_workitem(server)
  end

  defp start_workitem(%Enactment.Workitem{state: :allocated} = workitem, server)
       when is_pid(server) do
    {:ok, [%Enactment.Workitem{state: :started} = workitem]} =
      GenServer.call(server, {:start_workitems, [workitem.id]})

    workitem
  end

  defp setup_flow(%{out_arc_expression: out_arc_expression}) do
    cpnet =
      :simple_sequence
      |> ColouredFlow.CpnetBuilder.build_cpnet()
      |> Map.update!(:arcs, fn [in_arc, out_arc] ->
        out_arc_params =
          out_arc
          |> Map.from_struct()
          |> Map.take([:label, :place, :transition, :orientation])
          |> Map.to_list()
          |> Keyword.put(:expression, out_arc_expression)

        [
          in_arc,
          ColouredFlow.DefinitionHelpers.build_arc!(out_arc_params)
        ]
      end)

    flow = :flow |> build() |> flow_with_cpnet(cpnet) |> insert()

    [flow: flow]
  end

  defp setup_enactment(%{initial_markings: initial_markings, flow: flow}) do
    enactment =
      :enactment
      |> build(flow: flow)
      |> enactment_with_initial_markings(initial_markings)
      |> insert()

    pid = start_link_supervised!({Enactment, enactment_id: enactment.id}, id: enactment.id)

    [pid: pid, enactment: enactment]
  end
end
