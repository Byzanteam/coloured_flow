defmodule ColouredFlow.Runner.Enactment.LifespanTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  import ColouredFlow.MultiSet, only: :sigils

  alias ColouredFlow.Runner.Enactment.Lifespan

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

  describe "hibernate_after" do
    setup :setup_flow
    setup :setup_enactment

    @describetag cpnet: :simple_sequence

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "hibernates the GenServer after the configured idle duration",
         %{enactment: enactment} do
      # `hibernate_after` only kicks in when the GenServer's `noreply` timeout
      # is `:infinity` (see OTP `gen_server` `loop/5`); a finite timeout takes
      # priority and produces a synthetic `:timeout` message instead. The
      # production default for `Lifespan.timeout/1` is already `:infinity`, but
      # the test config sets it to `60_000`, so we override per-enactment to
      # exercise the hibernate path here.
      [enactment_server: enactment_server] =
        start_enactment(%{enactment: enactment}, timeout: :infinity, hibernate_after: 100)

      # Make sure the boot continues have completed before we start measuring
      # idle time, so the hibernate timer is actually counting down on an
      # empty mailbox.
      :ok = wait_enactment_requests_handled!(enactment_server)

      assert eventually(fn -> hibernated?(enactment_server) end),
             "expected #{inspect(enactment_server)} to hibernate within the deadline; " <>
               "current_function=#{inspect(Process.info(enactment_server, :current_function))}, " <>
               "status=#{inspect(Process.info(enactment_server, :status))}, " <>
               "messages=#{inspect(Process.info(enactment_server, :messages))}"
    end
  end

  describe "hibernate_after resolution" do
    test "hibernate_after_from_options prefers explicit option" do
      put_app_env(:hibernate_after, 7_000)

      assert Lifespan.hibernate_after_from_options(hibernate_after: 42) === 42
    end

    test "hibernate_after_from_options falls back to application env" do
      put_app_env(:hibernate_after, 7_000)

      assert Lifespan.hibernate_after_from_options([]) === 7_000
    end

    test "hibernate_after_from_options falls back to the built-in default" do
      delete_app_env_key(:hibernate_after)

      assert Lifespan.hibernate_after_from_options([]) === 15_000
    end

    test "hibernate_after/1 prefers per-state value" do
      put_app_env(:hibernate_after, 7_000)

      state = %Enactment{enactment_id: "irrelevant", hibernate_after: 42}

      assert Lifespan.hibernate_after(state) === 42
    end

    test "hibernate_after/1 falls back to application env when state value is nil" do
      put_app_env(:hibernate_after, 7_000)

      state = %Enactment{enactment_id: "irrelevant"}

      assert Lifespan.hibernate_after(state) === 7_000
    end
  end

  # A hibernated GenServer is observable in two ways:
  #
  # - `:current_function` becomes `{:gen_server, :loop_hibernate, _}` once the
  #   process has fully entered the hibernate loop, OR `{:erlang, :hibernate, _}`
  #   while it is in the middle of the transition.
  # - `:status` is `:waiting` and the heap is compacted.
  #
  # We accept either current_function form so the assertion is robust against
  # the exact moment we sample.
  defp hibernated?(pid) do
    case Process.info(pid, :current_function) do
      {:current_function, {:gen_server, :loop_hibernate, _arity}} -> true
      {:current_function, {:erlang, :hibernate, _arity}} -> true
      _other -> false
    end
  end

  # Poll the predicate up to ~1s, in 20ms slices, giving the runtime time to
  # transition into hibernation without burning a fixed long sleep.
  defp eventually(fun, deadline_ms \\ 1_000, slice_ms \\ 20) do
    wait_until(fun, System.monotonic_time(:millisecond) + deadline_ms, slice_ms)
  end

  defp wait_until(fun, deadline, slice) do
    if fun.() do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(slice)
        wait_until(fun, deadline, slice)
      end
    end
  end

  defp put_app_env(key, value) do
    snapshot_app_env()

    previous = Application.get_env(:coloured_flow, ColouredFlow.Runner.Enactment, [])

    Application.put_env(
      :coloured_flow,
      ColouredFlow.Runner.Enactment,
      Keyword.put(previous, key, value)
    )
  end

  defp delete_app_env_key(key) do
    snapshot_app_env()

    current = Application.get_env(:coloured_flow, ColouredFlow.Runner.Enactment, [])

    Application.put_env(
      :coloured_flow,
      ColouredFlow.Runner.Enactment,
      Keyword.delete(current, key)
    )
  end

  # Snapshot the full app-env entry once per test and restore it on exit, so
  # later tests see the env as the test started.
  defp snapshot_app_env do
    if Process.get(:lifespan_test_app_env_snapshotted) do
      :ok
    else
      Process.put(:lifespan_test_app_env_snapshotted, true)

      previous = Application.fetch_env(:coloured_flow, ColouredFlow.Runner.Enactment)
      on_exit(fn -> restore_app_env(previous) end)
    end
  end

  defp restore_app_env({:ok, value}) do
    Application.put_env(:coloured_flow, ColouredFlow.Runner.Enactment, value)
  end

  defp restore_app_env(:error) do
    Application.delete_env(:coloured_flow, ColouredFlow.Runner.Enactment)
  end
end
