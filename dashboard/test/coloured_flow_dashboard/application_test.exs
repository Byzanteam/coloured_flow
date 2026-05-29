defmodule ColouredFlowDashboard.ApplicationTest do
  use ExUnit.Case, async: true

  describe "supervision tree" do
    test "registers the dashboard top-level supervisor under its expected name" do
      assert is_pid(Process.whereis(ColouredFlowDashboard.Supervisor))
    end

    test "registers the shared Phoenix.PubSub under the configured name" do
      assert is_pid(Process.whereis(:coloured_flow_dashboard_pubsub))
    end

    test "the ColouredFlow.Runner.Supervisor is mounted with its registry and supervisor children" do
      assert runner_pid = Process.whereis(ColouredFlow.Runner.Supervisor)

      child_ids =
        runner_pid
        |> Supervisor.which_children()
        |> Enum.map(fn {id, _pid, _type, _modules} -> id end)

      assert ColouredFlow.Runner.Enactment.Registry in child_ids
      assert ColouredFlow.Runner.Enactment.Supervisor in child_ids
    end

    test "the enactment registry is reachable for via-tuple lookups" do
      assert Registry.lookup(
               ColouredFlow.Runner.Enactment.Registry,
               {:enactment, "no-such-enactment"}
             ) == []
    end

    test "wires the coloured_flow runner storage at our Repo" do
      cfg = Application.fetch_env!(:coloured_flow, ColouredFlow.Runner.Storage)
      # Tests use the in-memory ETS backend (see config/test.exs); production
      # config still pins `Storage.Default`.
      assert cfg[:storage] == ColouredFlow.Runner.Storage.InMemory
      assert cfg[:repo] == ColouredFlowDashboard.Repo
    end

    test "starts the dashboard Task.Supervisor for async bridge work" do
      assert is_pid(Process.whereis(ColouredFlowDashboard.TaskSupervisor))
    end

    test "starts the TelemetryBridge GenServer" do
      assert is_pid(Process.whereis(ColouredFlowDashboard.TelemetryBridge))
    end

    test "starts the in-memory runner storage when configured for tests" do
      assert is_pid(Process.whereis(ColouredFlow.Runner.Storage.InMemory))
    end
  end
end
