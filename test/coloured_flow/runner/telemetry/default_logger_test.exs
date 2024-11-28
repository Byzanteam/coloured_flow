defmodule ColouredFlow.Runner.Telemetry.DefaultLoggerTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  import ColouredFlow.MultiSet, only: :sigils

  import ExUnit.CaptureLog

  setup do
    level = Logger.level()
    Logger.configure(level: :warning)
    ColouredFlow.Runner.Telemetry.attach_default_logger(level: :warning, encode: true)

    on_exit(fn ->
      ColouredFlow.Runner.Telemetry.detach_default_logger()
      Logger.configure(level: level)
    end)
  end

  describe "start terminate event" do
    setup :setup_flow
    setup :setup_enactment

    @describetag cpnet: :simple_sequence

    @tag initial_markings: [%Marking{place: "output", tokens: ~MS[1]}]
    test "works", %{enactment: enactment} do
      log =
        capture_log(fn ->
          [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})
          wait_enactment_to_stop!(enactment_server)
        end)

      assert log =~ ~S|"event":"enactment:start"|
    end
  end

  describe "enactment terminate event" do
    setup :setup_flow
    setup :setup_enactment

    @describetag cpnet: :simple_sequence

    @tag initial_markings: [%Marking{place: "output", tokens: ~MS[1]}]
    test "works", %{enactment: enactment} do
      log =
        capture_log(fn ->
          [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})
          wait_enactment_to_stop!(enactment_server)
        end)

      assert log =~ ~S|"event":"enactment:terminate"|
    end
  end

  describe "enactment execption event" do
    setup :setup_cpnet

    setup %{cpnet: cpnet} do
      alias ColouredFlow.Definition.Expression
      alias ColouredFlow.Definition.TerminationCriteria

      terminate_criteria = %TerminationCriteria{
        markings: %TerminationCriteria.Markings{
          expression:
            Expression.build!("""
            case markings do
              %{"output" => output_ms} when multi_set_coefficient(output_ms, 1) > 0 ->
                1 / 0 > 1

              other ->
                false
            end
            """)
        }
      }

      [cpnet: Map.put(cpnet, :termination_criteria, terminate_criteria)]
    end

    setup :setup_flow
    setup :setup_enactment

    @describetag cpnet: :simple_sequence

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "inserts a transition log", %{enactment: enactment} do
      log =
        capture_log(fn ->
          [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})

          [%Enactment.Workitem{state: :enabled} = workitem] =
            get_enactment_workitems(enactment_server)

          workitem = start_workitem(workitem, enactment_server)

          {:ok, [_workitem]} =
            GenServer.call(enactment_server, {:complete_workitems, %{workitem.id => []}})

          wait_enactment_to_stop!(enactment_server)
        end)

      assert log =~ ~S|"event":"enactment:exception"|
      assert log =~ ~S|"exception_reason":"termination_criteria_evaluation"|
    end
  end
end
