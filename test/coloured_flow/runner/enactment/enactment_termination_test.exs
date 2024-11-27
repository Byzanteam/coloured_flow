defmodule ColouredFlow.Runner.Enactment.EnactmentTerminationTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  import ColouredFlow.MultiSet, only: :sigils

  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.TerminationCriteria
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment.EnactmentTermination
  alias ColouredFlow.Runner.Enactment.Workitem

  describe "check_explicit_termination/1" do
    test "works" do
      termination_criteria = %TerminationCriteria{
        markings: %TerminationCriteria.Markings{
          expression:
            Expression.build!("""
            match?(%{"output" => output_ms} when multi_set_coefficient(output_ms, 1) > 1, markings)
            """)
        }
      }

      assert :cont = EnactmentTermination.check_explicit_termination(termination_criteria, [])

      assert :cont =
               EnactmentTermination.check_explicit_termination(termination_criteria, [
                 %Marking{place: "output", tokens: ~MS[1]}
               ])

      assert {:stop, :explicit} =
               EnactmentTermination.check_explicit_termination(termination_criteria, [
                 %Marking{place: "output", tokens: ~MS[2**1]}
               ])
    end
  end

  describe "check_implicit_termination/1" do
    test "works" do
      assert {:stop, :implicit} = EnactmentTermination.check_implicit_termination([])

      assert :cont =
               EnactmentTermination.check_implicit_termination([
                 %Workitem{
                   id: Ecto.UUID.generate(),
                   state: :enabled,
                   binding_element: %BindingElement{
                     transition: "t",
                     binding: [],
                     to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
                   }
                 }
               ])
    end
  end

  describe "terminates implicitly" do
    setup :setup_flow
    setup :setup_enactment

    @describetag cpnet: :simple_sequence

    @tag initial_markings: [%Marking{place: "output", tokens: ~MS[1]}]
    test "terminates implicitly when no more enabled workitems at start", %{
      enactment: enactment,
      initial_markings: initial_markings
    } do
      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})
      wait_enactment_to_stop!(enactment_server)

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert :terminated === schema.state
      assert initial_markings === schema.data.final_markings
    end

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[2]}]
    test "terminates explicitly when no more enabled workitems after a workitem completed", %{
      enactment: enactment
    } do
      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})

      [%Enactment.Workitem{state: :enabled} = workitem] =
        get_enactment_workitems(enactment_server)

      workitem = start_workitem(workitem, enactment_server)

      {:ok, [_workitem]} =
        GenServer.call(enactment_server, {:complete_workitems, %{workitem.id => []}})

      wait_enactment_to_stop!(enactment_server)

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert :terminated === schema.state
      assert [%Marking{place: "output", tokens: ~MS[2]}] === schema.data.final_markings
    end
  end

  describe "terminates explicitly" do
    setup :setup_cpnet

    setup %{cpnet: cpnet} do
      alias ColouredFlow.Definition.Expression
      alias ColouredFlow.Definition.TerminationCriteria

      terminate_criteria = %TerminationCriteria{
        markings: %TerminationCriteria.Markings{
          expression:
            Expression.build!("""
            # it should terminate when the output marking has 2 tokens
            match?(%{"output" => output_ms} when multi_set_coefficient(output_ms, 1) === 2, markings)
            """)
        }
      }

      [cpnet: Map.put(cpnet, :termination_criteria, terminate_criteria)]
    end

    setup :setup_flow
    setup :setup_enactment

    @describetag cpnet: :simple_sequence

    @tag initial_markings: [%Marking{place: "output", tokens: ~MS[2**1]}]
    test "terminates explicitly when the terminate criteria are met at start", %{
      enactment: enactment,
      initial_markings: initial_markings
    } do
      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})
      wait_enactment_to_stop!(enactment_server)

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert :terminated === schema.state
      assert initial_markings === schema.data.final_markings
    end

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[2**1]}]
    test "terminates explicitly when the terminate criteria are met after a workitem completed",
         %{enactment: enactment} do
      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})

      [
        %Enactment.Workitem{state: :enabled} = workitem_1,
        %Enactment.Workitem{state: :enabled} = workitem_2
      ] = get_enactment_workitems(enactment_server)

      workitem_1 = start_workitem(workitem_1, enactment_server)
      workitem_2 = start_workitem(workitem_2, enactment_server)

      {:ok, [_workitem_1]} =
        GenServer.call(enactment_server, {:complete_workitems, %{workitem_1.id => []}})

      {:ok, [_workitem_2]} =
        GenServer.call(enactment_server, {:complete_workitems, %{workitem_2.id => []}})

      wait_enactment_to_stop!(enactment_server)

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert :terminated === schema.state
      assert [%Marking{place: "output", tokens: ~MS[2**1]}] === schema.data.final_markings
    end
  end

  defp wait_enactment_to_stop!(enactment_server, reason \\ :normal) do
    ref = Process.monitor(enactment_server)

    receive do
      {:DOWN, ^ref, :process, ^enactment_server, ^reason} -> :ok
    after
      500 -> flunk("Enactment server is expected to stop, but it's still running")
    end
  end
end
