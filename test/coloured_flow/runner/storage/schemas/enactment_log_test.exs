defmodule ColouredFlow.Runner.Storage.Schemas.EnactmentLogTest do
  @moduledoc """
  Persistence-level coverage for the fatal-reason enum stored in
  `enactment_logs.exception.reason`. Ensures every value in
  `ColouredFlow.Runner.Exception.__reasons__/0` round-trips through the
  `Ecto.Enum` field declared in the schema.
  """

  use ExUnit.Case, async: true

  alias ColouredFlow.Runner.Exception, as: PersistedException
  alias ColouredFlow.Runner.Storage.Schemas.Enactment
  alias ColouredFlow.Runner.Storage.Schemas.EnactmentLog

  describe "build_exception/3" do
    @reasons PersistedException.__reasons__()
    setup do
      enactment = %Enactment{id: Ecto.UUID.generate()}
      {:ok, enactment: enactment}
    end

    for reason <- @reasons do
      test "accepts persisted reason #{inspect(reason)}", %{enactment: enactment} do
        ex = %RuntimeError{message: "underlying"}
        changeset = EnactmentLog.build_exception(enactment, unquote(reason), ex)

        assert changeset.valid?

        log = Ecto.Changeset.apply_changes(changeset)
        assert log.state == :exception
        assert log.exception.reason == unquote(reason)
        assert log.exception.type == "RuntimeError"
        assert is_binary(log.exception.message)
        assert is_binary(log.exception.original)
      end
    end
  end

  describe "PersistedException.__reasons__/0" do
    test "covers exactly the design-doc reason set" do
      assert MapSet.new([
               :termination_criteria_evaluation,
               :state_drift,
               :snapshot_corrupt,
               :replay_failed,
               :enactment_data_missing,
               :cpnet_corrupt
             ]) == MapSet.new(PersistedException.__reasons__())
    end
  end
end
