defmodule ColouredFlow.Runner.Exceptions.AbnormalExitTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Runner.Exceptions.AbnormalExit

  describe "from_exit_reason/2" do
    @enactment_id "00000000-0000-0000-0000-000000000001"

    test "unwraps {exception, stacktrace} pair into the exception itself" do
      cause = RuntimeError.exception("boom")
      stacktrace = [{__MODULE__, :test, 0, []}]

      result = AbnormalExit.from_exit_reason(@enactment_id, {cause, stacktrace})

      assert %AbnormalExit{enactment_id: @enactment_id, cause: ^cause} = result
    end

    test "passes a bare exception struct through" do
      cause = ArgumentError.exception("bad arg")

      result = AbnormalExit.from_exit_reason(@enactment_id, cause)

      assert %AbnormalExit{enactment_id: @enactment_id, cause: ^cause} = result
    end

    test "wraps an atom exit reason in a RuntimeError" do
      result = AbnormalExit.from_exit_reason(@enactment_id, :killed)

      assert %AbnormalExit{enactment_id: @enactment_id, cause: %RuntimeError{} = cause} = result
      assert Exception.message(cause) === Exception.format_exit(:killed)
    end

    test "wraps an arbitrary tuple exit reason in a RuntimeError" do
      reason = {:bad_return_value, :oops}

      result = AbnormalExit.from_exit_reason(@enactment_id, reason)

      assert %AbnormalExit{enactment_id: @enactment_id, cause: %RuntimeError{} = cause} = result
      assert Exception.message(cause) === Exception.format_exit(reason)
    end
  end

  describe "message/1" do
    test "delegates to the wrapped cause's message" do
      cause = RuntimeError.exception("inner failure")

      exception =
        AbnormalExit.exception(
          enactment_id: "0000",
          cause: cause
        )

      assert Exception.message(exception) =~ "inner failure"
      assert Exception.message(exception) =~ "0000"
    end
  end
end
