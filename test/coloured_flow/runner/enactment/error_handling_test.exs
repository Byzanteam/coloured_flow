defmodule ColouredFlow.Runner.Enactment.ErrorHandlingTest do
  use ColouredFlow.RepoCase, async: true
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment, as: EnactmentServer
  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Exceptions
  alias ColouredFlow.Runner.Storage

  import Ecto.Query, only: [from: 2]

  describe "snapshot_corrupt self-heal" do
    setup :setup_flow
    setup :setup_enactment

    @describetag cpnet: :simple_sequence

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "writes an :exception log and replays from initial markings",
         %{enactment: enactment} do
      insert_corrupt_snapshot!(enactment.id, version: 1)

      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})

      :ok = wait_enactment_requests_handled!(enactment_server)

      logs = Repo.all(Schemas.EnactmentLog, enactment_id: enactment.id)

      assert Enum.any?(logs, fn log ->
               log.kind === :exception and
                 match?(%{reason: :snapshot_corrupt}, log.exception)
             end)

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert schema.state === :running

      [marking] = get_enactment_markings(enactment_server)
      assert marking.place === "input"
      assert marking.tokens === ~MS[1]
    end

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "rewrites a fresh snapshot after self-heal", %{enactment: enactment} do
      insert_corrupt_snapshot!(enactment.id, version: 5)

      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})
      :ok = wait_enactment_requests_handled!(enactment_server)

      # The runner overwrote the corrupt row on boot via the next take_snapshot.
      # Subsequent reads succeed and reflect the replayed state (no occurrences
      # exist yet, so version 0).
      assert {:ok, %Snapshot{version: 0}} = Storage.read_enactment_snapshot(enactment.id)
    end
  end

  describe "consecutive crash circuit breaker" do
    setup :setup_flow
    setup :setup_enactment

    @describetag cpnet: :simple_sequence

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "init shuts down once crash threshold is exceeded and flips state to :exception",
         %{enactment: enactment} do
      for _i <- 1..3 do
        :ok =
          Storage.exception_occurs(
            enactment.id,
            :abnormal_exit,
            Exceptions.AbnormalExit.from_exit_reason(enactment.id, :boom)
          )
      end

      ref =
        Process.monitor(
          start_supervised!(
            {EnactmentServer, [enactment_id: enactment.id]},
            id: enactment.id
          )
        )

      receive do
        {:DOWN, ^ref, :process, _pid, {:shutdown, :crash_threshold_exceeded}} -> :ok
        {:DOWN, ^ref, :process, _pid, reason} -> flunk("unexpected exit: #{inspect(reason)}")
      after
        500 -> flunk("enactment server did not stop")
      end

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert schema.state === :exception
    end

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "starts normally below threshold", %{enactment: enactment} do
      :ok =
        Storage.exception_occurs(
          enactment.id,
          :abnormal_exit,
          Exceptions.AbnormalExit.from_exit_reason(enactment.id, :boom)
        )

      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})

      assert is_pid(enactment_server)
      :ok = wait_enactment_requests_handled!(enactment_server)
    end

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "retry_enactment resets the streak so init succeeds",
         %{enactment: enactment} do
      for _i <- 1..3 do
        :ok =
          Storage.exception_occurs(
            enactment.id,
            :abnormal_exit,
            Exceptions.AbnormalExit.from_exit_reason(enactment.id, :boom)
          )
      end

      assert {:error, :crash_threshold_exceeded} =
               Storage.ensure_runnable(enactment.id)

      :ok = Storage.retry_enactment(enactment.id, [])

      assert :ok === Storage.ensure_runnable(enactment.id)

      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})
      :ok = wait_enactment_requests_handled!(enactment_server)
    end

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "init shuts down when state is already :exception", %{enactment: enactment} do
      query = from(e in Schemas.Enactment, where: e.id == ^enactment.id)
      Repo.update_all(query, set: [state: :exception])

      ref =
        Process.monitor(
          start_supervised!(
            {EnactmentServer, [enactment_id: enactment.id]},
            id: enactment.id
          )
        )

      receive do
        {:DOWN, ^ref, :process, _pid, {:shutdown, :already_in_exception}} -> :ok
        {:DOWN, ^ref, :process, _pid, reason} -> flunk("unexpected exit: #{inspect(reason)}")
      after
        500 -> flunk("enactment server did not stop")
      end
    end
  end

  describe "abnormal terminate logs :abnormal_exit" do
    setup :setup_flow
    setup :setup_enactment

    @describetag cpnet: :simple_sequence

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "non-shutdown stop triggers an :exception log row", %{enactment: enactment} do
      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})
      :ok = wait_enactment_requests_handled!(enactment_server)

      ref = Process.monitor(enactment_server)
      :ok = GenServer.stop(enactment_server, :crash_under_test, 500)

      receive do
        {:DOWN, ^ref, :process, ^enactment_server, _reason} -> :ok
      after
        500 -> ExUnit.Assertions.flunk("enactment server did not stop")
      end

      [log] = Repo.all(Schemas.EnactmentLog, enactment_id: enactment.id)

      assert log.kind === :exception
      assert log.exception.reason === :abnormal_exit
    end
  end

  defp insert_corrupt_snapshot!(enactment_id, version: version) do
    now = DateTime.utc_now()

    Ecto.Adapters.SQL.query!(
      Repo,
      """
      INSERT INTO coloured_flow.snapshots
        (enactment_id, version, markings, inserted_at, updated_at)
      VALUES ($1, $2, $3::jsonb, $4, $5)
      """,
      [Ecto.UUID.dump!(enactment_id), version, ~s(["not-a-marking-object"]), now, now]
    )
  end
end
