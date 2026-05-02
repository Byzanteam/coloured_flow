defmodule ColouredFlow.Runner.Storage.DefaultTest do
  use ColouredFlow.RepoCase, async: true

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Exceptions
  alias ColouredFlow.Runner.Storage.Default

  import ColouredFlow.MultiSet, only: :sigils

  describe "read_enactment_snapshot/1" do
    test "returns :error when no snapshot exists" do
      flow = :flow |> build() |> insert()
      enactment = :enactment |> build(flow: flow) |> insert()

      assert :error === Default.read_enactment_snapshot(enactment.id)
    end

    test "returns {:ok, snapshot} when a snapshot exists" do
      flow = :flow |> build() |> insert()
      enactment = :enactment |> build(flow: flow) |> insert()

      :ok =
        Default.take_enactment_snapshot(enactment.id, %Snapshot{
          version: 3,
          markings: [%Marking{place: "p", tokens: ~MS[1]}]
        })

      assert {:ok, %Snapshot{version: 3, markings: [%Marking{place: "p"}]}} =
               Default.read_enactment_snapshot(enactment.id)
    end

    test "returns {:error, {:snapshot_corrupt, _}} when the row cannot be decoded" do
      flow = :flow |> build() |> insert()
      enactment = :enactment |> build(flow: flow) |> insert()

      # Inject a snapshot row whose `markings` JSONB payload is shaped wrong:
      # `["not-a-marking-object"]` is a JSON array, but the codec expects an
      # array of objects with `place`/`tokens` keys. Going through raw SQL
      # bypasses the codec on insert so the failure surfaces only on read.
      insert_raw_snapshot!(enactment.id, ~s(["not-a-marking-object"]))

      assert {:error, {:snapshot_corrupt, _underlying}} =
               Default.read_enactment_snapshot(enactment.id)
    end

    test "treats Protocol.UndefinedError-class codec failures as corrupt" do
      flow = :flow |> build() |> insert()
      enactment = :enactment |> build(flow: flow) |> insert()

      # `tokens` is shaped as a list of pairs by the codec; inject a scalar
      # so deeper enumerable protocols raise.
      insert_raw_snapshot!(
        enactment.id,
        ~s([{"place": "p", "tokens": "not-a-list"}])
      )

      assert {:error, {:snapshot_corrupt, _underlying}} =
               Default.read_enactment_snapshot(enactment.id)
    end
  end

  describe "recover_from_corrupt_snapshot/2" do
    test "deletes corrupt snapshot row and records a recovery log entry" do
      flow = :flow |> build() |> insert()
      enactment = :enactment |> build(flow: flow) |> insert()

      :ok =
        Default.take_enactment_snapshot(enactment.id, %Snapshot{
          version: 1,
          markings: []
        })

      exception =
        Exceptions.SnapshotCorrupt.exception(
          enactment_id: enactment.id,
          underlying: RuntimeError.exception("boom")
        )

      assert :ok === Default.recover_from_corrupt_snapshot(enactment.id, exception)

      refute Repo.get_by(Schemas.Snapshot, enactment_id: enactment.id)

      [log] = Repo.all(Schemas.EnactmentLog, enactment_id: enactment.id)

      assert log.state === :running
      assert log.exception.reason === :snapshot_corrupt
      assert log.exception.type === inspect(Exceptions.SnapshotCorrupt)
    end
  end

  describe "record_crash/2 + consecutive_crashes_since_progress/1" do
    setup do
      flow = :flow |> build() |> insert()
      enactment = :enactment |> build(flow: flow) |> insert()
      [enactment: enactment]
    end

    test "record_crash inserts a non-fatal log row with reason=:crash", %{enactment: enactment} do
      exception = Exceptions.AbnormalExit.exception(reason: :killed)

      assert :ok === Default.record_crash(enactment.id, exception)

      [crash_log] = Repo.all(Schemas.EnactmentLog, enactment_id: enactment.id)

      assert crash_log.state === :running
      assert crash_log.exception.reason === :crash
    end

    test "counts crash log rows since enactment creation when no occurrences exist",
         %{enactment: enactment} do
      assert 0 === Default.consecutive_crashes_since_progress(enactment.id)

      for _i <- 1..3 do
        :ok =
          Default.record_crash(
            enactment.id,
            Exceptions.AbnormalExit.exception(reason: :boom)
          )
      end

      assert 3 === Default.consecutive_crashes_since_progress(enactment.id)
    end

    test "resets the count once a new occurrence is persisted", %{enactment: enactment} do
      :ok =
        Default.record_crash(
          enactment.id,
          Exceptions.AbnormalExit.exception(reason: :boom)
        )

      assert 1 === Default.consecutive_crashes_since_progress(enactment.id)

      workitem = :workitem |> build(enactment: enactment) |> insert()
      :occurrence |> build(enactment: enactment, workitem: workitem) |> insert()

      assert 0 === Default.consecutive_crashes_since_progress(enactment.id)
    end
  end

  defp insert_raw_snapshot!(enactment_id, markings_json) do
    now = DateTime.utc_now()

    Ecto.Adapters.SQL.query!(
      Repo,
      """
      INSERT INTO coloured_flow.snapshots
        (enactment_id, version, markings, inserted_at, updated_at)
      VALUES ($1, $2, $3::jsonb, $4, $5)
      """,
      [Ecto.UUID.dump!(enactment_id), 1, markings_json, now, now]
    )
  end
end
