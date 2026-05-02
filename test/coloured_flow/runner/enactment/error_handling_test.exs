defmodule ColouredFlow.Runner.Enactment.ErrorHandlingTest do
  use ColouredFlow.RepoCase, async: true
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment, as: EnactmentServer
  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Exceptions
  alias ColouredFlow.Runner.Storage

  describe "snapshot_corrupt self-heal" do
    setup :setup_flow
    setup :setup_enactment

    @describetag cpnet: :simple_sequence

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "writes a non-fatal :snapshot_corrupt log and replays from initial markings",
         %{enactment: enactment} do
      insert_corrupt_snapshot!(enactment.id, version: 1)

      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})

      :ok = wait_enactment_requests_handled!(enactment_server)

      logs = Repo.all(Schemas.EnactmentLog, enactment_id: enactment.id)

      assert Enum.any?(logs, fn log ->
               log.state === :running and
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
    test "init aborts via :ignore once crash threshold is exceeded",
         %{enactment: enactment} do
      for _i <- 1..3 do
        :ok =
          Storage.exception_occurs(
            enactment.id,
            :crash,
            Exceptions.AbnormalExit.exception(reason: :boom)
          )
      end

      # `start_supervised` records `:ignore` as `{:ok, :undefined}`.
      assert {:ok, :undefined} =
               start_supervised(
                 {EnactmentServer, [enactment_id: enactment.id]},
                 id: enactment.id
               )

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert schema.state === :exception

      [%{exception: %{reason: :restart_loop}}] =
        Schemas.EnactmentLog
        |> Repo.all(enactment_id: enactment.id)
        |> Enum.filter(&(&1.state === :exception))
    end

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "starts normally below threshold", %{enactment: enactment} do
      :ok =
        Storage.exception_occurs(
          enactment.id,
          :crash,
          Exceptions.AbnormalExit.exception(reason: :boom)
        )

      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})

      assert is_pid(enactment_server)
      :ok = wait_enactment_requests_handled!(enactment_server)
    end
  end

  describe "abnormal terminate logs :crash" do
    setup :setup_flow
    setup :setup_enactment

    @describetag cpnet: :simple_sequence

    @tag initial_markings: [%Marking{place: "input", tokens: ~MS[1]}]
    test "non-shutdown stop triggers a :crash log row", %{enactment: enactment} do
      [enactment_server: enactment_server] = start_enactment(%{enactment: enactment})
      :ok = wait_enactment_requests_handled!(enactment_server)

      ref = Process.monitor(enactment_server)
      :ok = GenServer.stop(enactment_server, :crash_under_test, 500)

      receive do
        {:DOWN, ^ref, :process, ^enactment_server, _reason} -> :ok
      after
        500 -> ExUnit.Assertions.flunk("enactment server did not stop")
      end

      [crash_log] = Repo.all(Schemas.EnactmentLog, enactment_id: enactment.id)

      assert crash_log.state === :running
      assert crash_log.exception.reason === :crash
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
