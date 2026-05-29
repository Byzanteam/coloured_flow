defmodule ColouredFlowDashboard.ApplicationTest do
  use ExUnit.Case, async: true

  describe "supervision tree" do
    test "boots the dashboard top-level supervisor" do
      assert pid = Process.whereis(ColouredFlowDashboard.Supervisor)
      assert Process.alive?(pid)
    end

    test "boots the shared Phoenix.PubSub under the configured name" do
      assert pid = Process.whereis(:coloured_flow_dashboard_pubsub)
      assert Process.alive?(pid)
    end

    test "boots the ColouredFlow.Runner.Supervisor and its children" do
      assert runner_pid = Process.whereis(ColouredFlow.Runner.Supervisor)
      assert Process.alive?(runner_pid)

      child_ids =
        runner_pid
        |> Supervisor.which_children()
        |> Enum.map(fn {id, _pid, _type, _modules} -> id end)

      assert ColouredFlow.Runner.Enactment.Registry in child_ids
      assert ColouredFlow.Runner.Enactment.Supervisor in child_ids
    end

    test "wires the coloured_flow runner storage at our Repo" do
      cfg = Application.fetch_env!(:coloured_flow, ColouredFlow.Runner.Storage)
      assert cfg[:storage] == ColouredFlow.Runner.Storage.Default
      assert cfg[:repo] == ColouredFlowDashboard.Repo
    end
  end
end
