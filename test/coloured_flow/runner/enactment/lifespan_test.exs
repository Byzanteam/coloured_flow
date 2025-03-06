defmodule ColouredFlow.Runner.Enactment.LifespanTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  import ColouredFlow.MultiSet, only: :sigils

  describe "terminated due to inactivity" do
    setup :setup_flow
    setup :setup_enactment

    @describetag cpnet: :simple_sequence

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "works", %{enactment: enactment} do
      [enactment_server: enactment_server] =
        start_enactment(%{enactment: enactment}, timeout: 10)

      ref = Process.monitor(enactment_server)

      wait_enactment_to_stop!(enactment_server)

      assert_received {
        :DOWN,
        ^ref,
        :process,
        ^enactment_server,
        {:shutdown, "Terminated due to inactivity"}
      }
    end
  end
end
