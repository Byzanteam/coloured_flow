defmodule ColouredFlow.Runner.Storage.DefaultTest do
  use ColouredFlow.RepoCase, async: true

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Exceptions
  alias ColouredFlow.Runner.Storage.Default

  import ColouredFlow.MultiSet, only: :sigils
  import Ecto.Query, only: [from: 2]

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

    test "returns {:error, %SnapshotCorrupt{}} when the row cannot be decoded" do
      flow = :flow |> build() |> insert()
      enactment = :enactment |> build(flow: flow) |> insert()

      # Inject a snapshot row whose `markings` JSONB payload is shaped wrong:
      # `["not-a-marking-object"]` is a JSON array, but the codec expects an
      # array of objects with `place`/`tokens` keys. Going through raw SQL
      # bypasses the codec on insert so the failure surfaces only on read.
      insert_raw_snapshot!(enactment.id, ~s(["not-a-marking-object"]))

      assert {:error, %Exceptions.SnapshotCorrupt{} = exception} =
               Default.read_enactment_snapshot(enactment.id)

      assert exception.enactment_id === enactment.id
      assert is_exception(exception.cause)
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

      assert {:error, %Exceptions.SnapshotCorrupt{}} =
               Default.read_enactment_snapshot(enactment.id)
    end
  end

  describe "exception_occurs/3" do
    setup do
      flow = :flow |> build() |> insert()
      enactment = :enactment |> build(flow: flow) |> insert()
      [enactment: enactment]
    end

    test "writes an :abnormal_exit log row without flipping enactment state",
         %{enactment: enactment} do
      exception =
        Exceptions.AbnormalExit.from_exit_reason(enactment.id, :killed)

      assert :ok === Default.exception_occurs(enactment.id, :abnormal_exit, exception)

      [log] = Repo.all(Schemas.EnactmentLog, enactment_id: enactment.id)
      assert log.kind === :exception
      assert log.exception.reason === :abnormal_exit

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert schema.state === :running
    end

    test "writes a :snapshot_corrupt log row without flipping state",
         %{enactment: enactment} do
      exception =
        Exceptions.SnapshotCorrupt.exception(
          enactment_id: enactment.id,
          cause: RuntimeError.exception("boom")
        )

      assert :ok === Default.exception_occurs(enactment.id, :snapshot_corrupt, exception)

      [log] = Repo.all(Schemas.EnactmentLog, enactment_id: enactment.id)
      assert log.kind === :exception
      assert log.exception.reason === :snapshot_corrupt

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert schema.state === :running
    end

    test "writes an :invalid_termination_criteria log row without flipping state",
         %{enactment: enactment} do
      exception = ArgumentError.exception("bad criteria")

      assert :ok ===
               Default.exception_occurs(
                 enactment.id,
                 :invalid_termination_criteria,
                 exception
               )

      [log] = Repo.all(Schemas.EnactmentLog, enactment_id: enactment.id)
      assert log.kind === :exception
      assert log.exception.reason === :invalid_termination_criteria

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert schema.state === :running
    end
  end

  describe "retry_enactment/2" do
    setup do
      flow = :flow |> build() |> insert()

      enactment =
        :enactment
        |> build(flow: flow)
        |> Map.put(:state, :exception)
        |> insert()

      [enactment: enactment]
    end

    test "writes a :retried log and flips state to :running", %{enactment: enactment} do
      assert :ok === Default.retry_enactment(enactment.id, message: "operator reoffer")

      [log] = Repo.all(Schemas.EnactmentLog, enactment_id: enactment.id)
      assert log.kind === :retried
      assert log.retry.message === "operator reoffer"

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert schema.state === :running
    end

    test "accepts no message option", %{enactment: enactment} do
      assert :ok === Default.retry_enactment(enactment.id, [])

      [log] = Repo.all(Schemas.EnactmentLog, enactment_id: enactment.id)
      assert log.kind === :retried
      assert log.retry.message === nil
    end
  end

  describe "ensure_runnable/1" do
    setup do
      flow = :flow |> build() |> insert()
      enactment = :enactment |> build(flow: flow) |> insert()
      [enactment: enactment]
    end

    test "returns :ok on a fresh enactment", %{enactment: enactment} do
      assert :ok === Default.ensure_runnable(enactment.id)

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert schema.state === :running
    end

    test "returns :ok with fewer than 3 :exception logs", %{enactment: enactment} do
      :ok =
        Default.exception_occurs(
          enactment.id,
          :abnormal_exit,
          Exceptions.AbnormalExit.from_exit_reason(enactment.id, :boom)
        )

      assert :ok === Default.ensure_runnable(enactment.id)
    end

    test "trips and flips state when the last 3 logs are all :exception",
         %{enactment: enactment} do
      for _i <- 1..3 do
        :ok =
          Default.exception_occurs(
            enactment.id,
            :abnormal_exit,
            Exceptions.AbnormalExit.from_exit_reason(enactment.id, :boom)
          )
      end

      assert {:error, :crash_threshold_exceeded} = Default.ensure_runnable(enactment.id)

      schema = Repo.get(Schemas.Enactment, enactment.id)
      assert schema.state === :exception
    end

    test "trips on mixed exception reasons", %{enactment: enactment} do
      :ok =
        Default.exception_occurs(
          enactment.id,
          :abnormal_exit,
          Exceptions.AbnormalExit.from_exit_reason(enactment.id, :boom)
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
          :invalid_termination_criteria,
          ArgumentError.exception("bad")
        )

      assert {:error, :crash_threshold_exceeded} = Default.ensure_runnable(enactment.id)
    end

    test "stays runnable when a non-exception log breaks the streak",
         %{enactment: enactment} do
      :ok =
        Default.exception_occurs(
          enactment.id,
          :abnormal_exit,
          Exceptions.AbnormalExit.from_exit_reason(enactment.id, :boom)
        )

      # Restore the state so retry_enactment can flip it back legitimately, then
      # squeeze a :retried log between two more exception logs.
      query = from(e in Schemas.Enactment, where: e.id == ^enactment.id)
      Repo.update_all(query, set: [state: :exception])

      :ok = Default.retry_enactment(enactment.id, [])

      :ok =
        Default.exception_occurs(
          enactment.id,
          :abnormal_exit,
          Exceptions.AbnormalExit.from_exit_reason(enactment.id, :boom)
        )

      :ok =
        Default.exception_occurs(
          enactment.id,
          :abnormal_exit,
          Exceptions.AbnormalExit.from_exit_reason(enactment.id, :boom)
        )

      assert :ok === Default.ensure_runnable(enactment.id)
    end

    test "returns :terminated when the enactment is already terminated" do
      flow = :flow |> build() |> insert()

      enactment =
        :enactment
        |> build(flow: flow)
        |> Map.put(:state, :terminated)
        |> insert()

      assert {:error, :terminated} = Default.ensure_runnable(enactment.id)
    end

    test "returns :already_in_exception when state is :exception" do
      flow = :flow |> build() |> insert()

      enactment =
        :enactment
        |> build(flow: flow)
        |> Map.put(:state, :exception)
        |> insert()

      assert {:error, :already_in_exception} = Default.ensure_runnable(enactment.id)
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
