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

      assert {:error, {:snapshot_corrupt, _cause}} =
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

      assert {:error, {:snapshot_corrupt, _cause}} =
               Default.read_enactment_snapshot(enactment.id)
    end
  end

  describe "exception_occurs/3 (non-fatal reasons)" do
    setup do
      flow = :flow |> build() |> insert()
      enactment = :enactment |> build(flow: flow) |> insert()
      [enactment: enactment]
    end

    test "writes a :crash log row without flipping enactment state", %{enactment: enactment} do
      exception = Exceptions.AbnormalExit.exception(reason: :killed)

      assert :ok === Default.exception_occurs(enactment.id, :crash, exception)

      [crash_log] = Repo.all(Schemas.EnactmentLog, enactment_id: enactment.id)
      assert crash_log.state === :running
      assert crash_log.exception.reason === :crash

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert schema.state === :running
    end

    test "writes a :snapshot_corrupt log row without flipping state", %{enactment: enactment} do
      exception =
        Exceptions.SnapshotCorrupt.exception(
          enactment_id: enactment.id,
          cause: RuntimeError.exception("boom")
        )

      assert :ok === Default.exception_occurs(enactment.id, :snapshot_corrupt, exception)

      [log] = Repo.all(Schemas.EnactmentLog, enactment_id: enactment.id)
      assert log.state === :running
      assert log.exception.reason === :snapshot_corrupt

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert schema.state === :running
    end
  end

  describe "crash_threshold_exceeded?/1" do
    setup do
      flow = :flow |> build() |> insert()
      enactment = :enactment |> build(flow: flow) |> insert()
      [enactment: enactment]
    end

    test "returns false when fewer than 3 logs exist", %{enactment: enactment} do
      refute Default.crash_threshold_exceeded?(enactment.id)

      :ok =
        Default.exception_occurs(
          enactment.id,
          :crash,
          Exceptions.AbnormalExit.exception(reason: :boom)
        )

      refute Default.crash_threshold_exceeded?(enactment.id)
    end

    test "returns true when the last 3 logs are all :crash", %{enactment: enactment} do
      for _i <- 1..3 do
        :ok =
          Default.exception_occurs(
            enactment.id,
            :crash,
            Exceptions.AbnormalExit.exception(reason: :boom)
          )
      end

      assert Default.crash_threshold_exceeded?(enactment.id)
    end

    test "returns false when a non-crash log breaks the streak", %{enactment: enactment} do
      :ok =
        Default.exception_occurs(
          enactment.id,
          :crash,
          Exceptions.AbnormalExit.exception(reason: :boom)
        )

      :ok =
        Default.exception_occurs(
          enactment.id,
          :snapshot_corrupt,
          Exceptions.SnapshotCorrupt.exception(
            enactment_id: enactment.id,
            cause: RuntimeError.exception("boom")
          )
        )

      :ok =
        Default.exception_occurs(
          enactment.id,
          :crash,
          Exceptions.AbnormalExit.exception(reason: :boom)
        )

      refute Default.crash_threshold_exceeded?(enactment.id)
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
