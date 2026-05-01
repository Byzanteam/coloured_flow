defmodule ColouredFlow.Runner.ErrorsTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.ColourSet.ColourSetMismatch
  alias ColouredFlow.Expression.InvalidResult
  alias ColouredFlow.Runner.Errors
  alias ColouredFlow.Runner.Exceptions

  describe "tier/1" do
    test "classifies operational errors as Tier 1" do
      assert 1 ==
               Errors.tier(
                 Exceptions.NonLiveWorkitem.exception(
                   id: "id",
                   enactment_id: "eid"
                 )
               )

      assert 1 ==
               Errors.tier(
                 Exceptions.InvalidWorkitemTransition.exception(
                   id: "id",
                   enactment_id: "eid",
                   state: :started,
                   transition: :start
                 )
               )

      assert 1 ==
               Errors.tier(
                 Exceptions.UnsufficientTokensToConsume.exception(
                   enactment_id: "eid",
                   place: "p",
                   tokens: ColouredFlow.MultiSet.new()
                 )
               )

      assert 1 ==
               Errors.tier(Exceptions.UnboundActionOutput.exception(transition: "t", output: :v))
    end

    test "classifies new caller-safe wrapper exceptions as Tier 1" do
      assert 1 == Errors.tier(Exceptions.EnactmentNotRunning.exception(enactment_id: "eid"))

      assert 1 ==
               Errors.tier(
                 Exceptions.EnactmentTimeout.exception(enactment_id: "eid", timeout: 5_000)
               )

      assert 1 ==
               Errors.tier(
                 Exceptions.EnactmentCallFailed.exception(enactment_id: "eid", reason: :killed)
               )

      assert 1 ==
               Errors.tier(
                 Exceptions.StoragePersistenceFailed.exception(operation: :insert, context: %{})
               )
    end

    test "classifies user-supplied data errors as Tier 1" do
      assert 1 == Errors.tier(ColourSetMismatch.exception(colour_set: nil, value: 0))

      assert 1 ==
               Errors.tier(
                 InvalidResult.exception(
                   expression: %ColouredFlow.Definition.Expression{code: "x", expr: nil},
                   message: "bad"
                 )
               )
    end

    test "classifies foreign exceptions as Tier 3" do
      assert 3 == Errors.tier(%RuntimeError{message: "boom"})
      assert 3 == Errors.tier(%ArgumentError{message: "bad arg"})
    end

    test "classifies enactment-fatal exceptions as Tier 2" do
      assert 2 ==
               Errors.tier(
                 Exceptions.StateDrift.exception(
                   enactment_id: "eid",
                   operation: :start_workitems,
                   context: %{}
                 )
               )

      assert 2 == Errors.tier(Exceptions.SnapshotCorrupt.exception(enactment_id: "eid"))
      assert 2 == Errors.tier(Exceptions.ReplayFailed.exception(enactment_id: "eid"))

      assert 2 ==
               Errors.tier(
                 Exceptions.EnactmentDataMissing.exception(
                   enactment_id: "eid",
                   missing: :enactment
                 )
               )

      assert 2 == Errors.tier(Exceptions.CpnetCorrupt.exception(enactment_id: "eid"))
    end
  end

  describe "error_code/1" do
    test "returns the struct field for runner exceptions" do
      assert :non_live_workitem ==
               Errors.error_code(
                 Exceptions.NonLiveWorkitem.exception(id: "id", enactment_id: "eid")
               )

      assert :enactment_not_running ==
               Errors.error_code(Exceptions.EnactmentNotRunning.exception(enactment_id: "eid"))

      assert :colour_set_mismatch ==
               Errors.error_code(ColourSetMismatch.exception(colour_set: nil, value: 0))
    end

    test "returns :unknown for foreign exceptions" do
      assert :unknown == Errors.error_code(%RuntimeError{message: "boom"})
    end
  end

  describe "to_persisted_reason/1" do
    test "maps InvalidResult to :termination_criteria_evaluation" do
      ex =
        InvalidResult.exception(
          expression: %ColouredFlow.Definition.Expression{code: "x", expr: nil},
          message: "bad"
        )

      assert :termination_criteria_evaluation == Errors.to_persisted_reason(ex)
    end

    test "returns nil for non-fatal exceptions" do
      assert is_nil(
               Errors.to_persisted_reason(
                 Exceptions.NonLiveWorkitem.exception(id: "id", enactment_id: "eid")
               )
             )

      assert is_nil(Errors.to_persisted_reason(%RuntimeError{message: "x"}))
    end

    test "maps each Tier 2 exception to its persisted reason" do
      assert :state_drift ==
               Errors.to_persisted_reason(
                 Exceptions.StateDrift.exception(
                   enactment_id: "eid",
                   operation: :start_workitems,
                   context: %{}
                 )
               )

      assert :snapshot_corrupt ==
               Errors.to_persisted_reason(
                 Exceptions.SnapshotCorrupt.exception(enactment_id: "eid")
               )

      assert :replay_failed ==
               Errors.to_persisted_reason(Exceptions.ReplayFailed.exception(enactment_id: "eid"))

      assert :enactment_data_missing ==
               Errors.to_persisted_reason(
                 Exceptions.EnactmentDataMissing.exception(
                   enactment_id: "eid",
                   missing: :enactment
                 )
               )

      assert :cpnet_corrupt ==
               Errors.to_persisted_reason(Exceptions.CpnetCorrupt.exception(enactment_id: "eid"))
    end
  end

  describe "build_exception/2" do
    test "builds StateDrift from context" do
      ex =
        Errors.build_exception(:state_drift, %{
          enactment_id: "eid",
          operation: :start_workitems,
          context: %{expected: 1, actual: 0}
        })

      assert %Exceptions.StateDrift{
               enactment_id: "eid",
               operation: :start_workitems,
               context: %{expected: 1, actual: 0},
               error_code: :state_drift
             } = ex
    end

    test "builds SnapshotCorrupt with optional underlying" do
      ex =
        Errors.build_exception(:snapshot_corrupt, %{
          enactment_id: "eid",
          underlying: %RuntimeError{message: "codec"}
        })

      assert %Exceptions.SnapshotCorrupt{
               enactment_id: "eid",
               underlying: %RuntimeError{},
               error_code: :snapshot_corrupt
             } = ex
    end

    test "builds ReplayFailed" do
      ex = Errors.build_exception(:replay_failed, %{enactment_id: "eid", underlying: :boom})

      assert %Exceptions.ReplayFailed{
               enactment_id: "eid",
               underlying: :boom,
               error_code: :replay_failed
             } = ex
    end

    test "builds EnactmentDataMissing" do
      ex =
        Errors.build_exception(:enactment_data_missing, %{
          enactment_id: "eid",
          missing: :flow
        })

      assert %Exceptions.EnactmentDataMissing{
               enactment_id: "eid",
               missing: :flow,
               error_code: :enactment_data_missing
             } = ex
    end

    test "builds CpnetCorrupt" do
      ex =
        Errors.build_exception(:cpnet_corrupt, %{
          enactment_id: "eid",
          underlying: %ArgumentError{message: "bad atom"}
        })

      assert %Exceptions.CpnetCorrupt{
               enactment_id: "eid",
               underlying: %ArgumentError{},
               error_code: :cpnet_corrupt
             } = ex
    end

    test "passes through the InvalidResult exception for termination_criteria_evaluation" do
      original =
        ColouredFlow.Expression.InvalidResult.exception(
          expression: %ColouredFlow.Definition.Expression{code: "x", expr: nil},
          message: "bad"
        )

      assert ^original =
               Errors.build_exception(:termination_criteria_evaluation, %{exception: original})
    end
  end

  describe "lifecycle?/1" do
    test "true when exception has a persisted reason" do
      ex =
        InvalidResult.exception(
          expression: %ColouredFlow.Definition.Expression{code: "x", expr: nil},
          message: "bad"
        )

      assert Errors.lifecycle?(ex)
    end

    test "false otherwise" do
      refute Errors.lifecycle?(
               Exceptions.NonLiveWorkitem.exception(id: "id", enactment_id: "eid")
             )

      refute Errors.lifecycle?(%RuntimeError{message: "x"})
    end
  end
end
