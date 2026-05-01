defmodule ColouredFlow.Runner.Enactment.WorkitemTransitionTest do
  @moduledoc """
  Tests for the caller-safe wrapper around `GenServer.call/3` in
  `WorkitemTransition`. Covers the full `:exit` surface defined in
  `error_handling_design.md`.
  """

  use ExUnit.Case, async: true

  alias ColouredFlow.Runner.Enactment.Registry, as: EnactmentRegistry
  alias ColouredFlow.Runner.Enactment.Supervisor, as: EnactmentSupervisor
  alias ColouredFlow.Runner.Enactment.WorkitemTransition
  alias ColouredFlow.Runner.Exceptions

  describe "start_workitem/2 against a non-running enactment" do
    test "returns EnactmentNotRunning when the enactment was never started" do
      enactment_id = Ecto.UUID.generate()

      assert {:error, %Exceptions.EnactmentNotRunning{} = ex} =
               WorkitemTransition.start_workitem(enactment_id, Ecto.UUID.generate())

      assert ex.enactment_id == enactment_id
      assert ex.reason == :not_started
      assert ex.error_code == :enactment_not_running
    end
  end

  describe "complete_workitem/2 against a non-running enactment" do
    test "returns EnactmentNotRunning when the enactment was never started" do
      enactment_id = Ecto.UUID.generate()

      assert {:error, %Exceptions.EnactmentNotRunning{} = ex} =
               WorkitemTransition.complete_workitem(enactment_id, {Ecto.UUID.generate(), []})

      assert ex.enactment_id == enactment_id
      assert ex.reason == :not_started
    end
  end

  describe "Enactment.Supervisor.terminate_enactment/2 against a non-running enactment" do
    test "returns EnactmentNotRunning when the enactment was never started" do
      enactment_id = Ecto.UUID.generate()

      assert {:error, %Exceptions.EnactmentNotRunning{} = ex} =
               EnactmentSupervisor.terminate_enactment(enactment_id)

      assert ex.enactment_id == enactment_id
      assert ex.reason == :not_started
    end
  end

  describe "call_enactment/3 :exit surface coverage" do
    test "EnactmentTimeout when the called process does not reply within the timeout" do
      enactment_id = Ecto.UUID.generate()
      {pid, ref} = spawn_registered_stub(enactment_id, fn -> :stall end)

      try do
        assert {:error, %Exceptions.EnactmentTimeout{} = ex} =
                 WorkitemTransition.call_enactment(enactment_id, :anything, 50)

        assert ex.enactment_id == enactment_id
        assert ex.timeout == 50
      after
        send(pid, :stop)
        await_down(pid, ref)
      end
    end

    test "EnactmentNotRunning(:stopped_during_call) when called process exits :normal mid-call" do
      enactment_id = Ecto.UUID.generate()
      {_pid, ref} = spawn_registered_stub(enactment_id, fn -> {:exit_on_call, :normal} end)

      assert {:error, %Exceptions.EnactmentNotRunning{} = ex} =
               WorkitemTransition.call_enactment(enactment_id, :anything, 1_000)

      assert ex.enactment_id == enactment_id
      assert ex.reason == :stopped_during_call

      await_down(:_pid, ref)
    end

    test "EnactmentNotRunning(:shutting_down) when called process exits {:shutdown, _} mid-call" do
      enactment_id = Ecto.UUID.generate()

      {_pid, ref} =
        spawn_registered_stub(enactment_id, fn -> {:exit_on_call, {:shutdown, :test}} end)

      assert {:error, %Exceptions.EnactmentNotRunning{} = ex} =
               WorkitemTransition.call_enactment(enactment_id, :anything, 1_000)

      assert ex.enactment_id == enactment_id
      assert ex.reason == :shutting_down

      await_down(:_pid, ref)
    end

    test "EnactmentCallFailed catch-all when called process exits with arbitrary reason" do
      enactment_id = Ecto.UUID.generate()

      {_pid, ref} =
        spawn_registered_stub(enactment_id, fn -> {:exit_on_call, :custom_crash_reason} end)

      assert {:error, %Exceptions.EnactmentCallFailed{} = ex} =
               WorkitemTransition.call_enactment(enactment_id, :anything, 1_000)

      assert ex.enactment_id == enactment_id
      assert ex.reason == :custom_crash_reason
      assert ex.error_code == :enactment_call_failed

      await_down(:_pid, ref)
    end

    test "EnactmentCallFailed when called process is killed mid-call" do
      enactment_id = Ecto.UUID.generate()
      {pid, ref} = spawn_registered_stub(enactment_id, fn -> :stall end)

      task =
        Task.async(fn ->
          WorkitemTransition.call_enactment(enactment_id, :anything, 1_000)
        end)

      # Give the call time to dispatch before we kill the stub.
      Process.sleep(10)
      Process.exit(pid, :kill)

      assert {:error, %Exceptions.EnactmentCallFailed{} = ex} = Task.await(task, 1_000)
      assert ex.enactment_id == enactment_id
      assert ex.reason == :killed

      await_down(pid, ref)
    end

    test "EnactmentNotRunning(:not_started) when whereis succeeds but pid dies before call" do
      # Race between Registry.whereis/1 returning a pid and GenServer.call/3
      # reaching it. The wrapper must surface the resulting :noproc as a
      # typed exception, not as an exit signal.
      enactment_id = Ecto.UUID.generate()
      {pid, ref} = spawn_registered_stub(enactment_id, fn -> :stall end)

      Process.exit(pid, :kill)
      await_down(pid, ref)

      assert {:error, %Exceptions.EnactmentNotRunning{} = ex} =
               WorkitemTransition.call_enactment(enactment_id, :anything, 100)

      assert ex.enactment_id == enactment_id
      assert ex.reason == :not_started
    end

    test "re-exits :calling_self instead of swallowing programming bugs" do
      # Programmer error: calling the enactment from within itself would
      # deadlock. The wrapper deliberately re-exits so the bug surfaces
      # instead of being normalised into a typed error.
      enactment_id = Ecto.UUID.generate()

      parent = self()

      {pid, ref} =
        spawn_registered_stub(enactment_id, fn ->
          # Trigger the :calling_self path by calling itself.
          send(parent, {:result, catch_exit(GenServer.call(self(), :anything, 50))})
          :stall
        end)

      assert_receive {:result, exit_reason}, 1_000

      # GenServer.call/3 against self exits with {:calling_self, _}.
      case exit_reason do
        {:calling_self, _info} -> :ok
        :calling_self -> :ok
        _other -> flunk("Expected :calling_self exit, got: #{inspect(exit_reason)}")
      end

      send(pid, :stop)
      await_down(pid, ref)
    end
  end

  describe "Registry.whereis/1" do
    test "returns :error when no process is registered for the key" do
      assert :error == EnactmentRegistry.whereis({:enactment, Ecto.UUID.generate()})
    end

    test "returns {:ok, pid} when a process is registered" do
      enactment_id = Ecto.UUID.generate()
      {pid, ref} = spawn_registered_stub(enactment_id, fn -> :stall end)

      try do
        assert {:ok, ^pid} = EnactmentRegistry.whereis({:enactment, enactment_id})
      after
        send(pid, :stop)
        await_down(pid, ref)
      end
    end
  end

  defp spawn_registered_stub(enactment_id, behaviour_fun) do
    parent = self()

    pid =
      spawn(fn ->
        {:ok, _owner} =
          Registry.register(EnactmentRegistry, {:enactment, enactment_id}, nil)

        send(parent, {:registered, self()})

        case behaviour_fun.() do
          :stall ->
            receive do
              :stop -> :ok
            end

          {:exit_on_call, exit_reason} ->
            receive do
              {:"$gen_call", _from, _msg} -> exit(exit_reason)
            end
        end
      end)

    ref = Process.monitor(pid)

    receive do
      {:registered, ^pid} -> :ok
    after
      500 -> raise "stub registration timed out"
    end

    {pid, ref}
  end

  defp await_down(_pid, ref) do
    receive do
      {:DOWN, ^ref, :process, _object, _reason} -> :ok
    after
      1_000 -> :ok
    end
  end
end
