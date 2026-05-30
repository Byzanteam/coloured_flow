defmodule ColouredFlowDashboard.EnactmentResumerTest do
  # `async: false` because the test mutates the singleton
  # `ColouredFlow.Runner.Enactment.Supervisor` + `Runner.Enactment.Registry`.
  use ColouredFlowDashboard.DataCase, async: false

  import ExUnit.CaptureLog

  alias ColouredFlowDashboard.EnactmentResumer
  alias ColouredFlowDashboard.Seed
  alias ColouredFlowDashboard.Seeds.ApprovalFlow

  setup do
    # Earlier tests may leave enactment GenServers under the supervisor.
    # Terminate them so each case starts from a known empty registry.
    # InMemory ETS rows survive (the table is `:protected`); the resumer
    # treats them all as adoptable, which is exactly the boot scenario we
    # are exercising.
    terminate_all_enactments()
    on_exit(&terminate_all_enactments/0)
    :ok
  end

  describe "init/1" do
    test "returns :ignore when :resume_enactments is disabled" do
      assert :ignore = EnactmentResumer.init(enabled: false)
    end
  end

  describe "boot sweep" do
    test "adopts an existing :running enactment row into the Runner supervisor" do
      :ok = Seed.run()
      enactment_id = Seed.enactment_id(ApprovalFlow)
      assert is_binary(enactment_id)

      # Tear the live GenServer down to simulate a fresh phx boot where the
      # storage row outlives the Runner supervisor. The ETS row stays.
      :ok = terminate_enactment(enactment_id)
      refute alive?(enactment_id)

      assert {:ok, pid} =
               GenServer.start_link(EnactmentResumer, enabled: true)

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000

      assert alive?(enactment_id)
    end

    test "resuming an already-running enactment is idempotent" do
      :ok = Seed.run()
      enactment_id = Seed.enactment_id(ApprovalFlow)
      assert alive?(enactment_id)
      pid_before = whereis(enactment_id)

      log =
        with_info_logs(fn ->
          {:ok, resumer} = GenServer.start_link(EnactmentResumer, enabled: true)
          ref = Process.monitor(resumer)
          assert_receive {:DOWN, ^ref, :process, ^resumer, :normal}, 1_000
        end)

      assert log =~ "[EnactmentResumer] resumed"
      assert whereis(enactment_id) == pid_before
    end

    test "sweep with no rows completes cleanly and emits the summary log" do
      log =
        with_info_logs(fn ->
          {:ok, resumer} = GenServer.start_link(EnactmentResumer, enabled: true)
          ref = Process.monitor(resumer)
          assert_receive {:DOWN, ^ref, :process, ^resumer, :normal}, 1_000
        end)

      assert log =~ "[EnactmentResumer] resumed"
    end
  end

  defp alive?(enactment_id), do: is_pid(whereis(enactment_id))

  defp whereis(enactment_id) do
    GenServer.whereis(
      {:via, Registry, {ColouredFlow.Runner.Enactment.Registry, {:enactment, enactment_id}}}
    )
  end

  defp terminate_enactment(enactment_id) do
    sup = ColouredFlow.Runner.Enactment.Supervisor

    case whereis(enactment_id) do
      pid when is_pid(pid) ->
        ref = Process.monitor(pid)
        :ok = DynamicSupervisor.terminate_child(sup, pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
        :ok

      _other ->
        :ok
    end
  end

  defp terminate_all_enactments do
    sup = ColouredFlow.Runner.Enactment.Supervisor

    for {_id, pid, _type, _mods} <- DynamicSupervisor.which_children(sup), is_pid(pid) do
      ref = Process.monitor(pid)
      :ok = DynamicSupervisor.terminate_child(sup, pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        1_000 -> :ok
      end
    end
  end

  defp with_info_logs(fun) do
    original = Logger.level()
    Logger.configure(level: :info)

    try do
      capture_log(fun)
    after
      Logger.configure(level: original)
    end
  end
end
