defmodule ColouredFlow.Runner.ActionHandlerTest do
  # credo:disable-for-this-file Credo.Check.Readability.Specs
  use ExUnit.Case, async: true

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.MultiSet
  alias ColouredFlow.Runner.ActionHandler

  describe "safe_invoke/3" do
    defmodule SilentHandler do
      @behaviour ActionHandler
      def on_enactment_start(_ctx), do: :ok
    end

    defmodule CrashyHandler do
      @behaviour ActionHandler
      def on_enactment_start(_ctx), do: raise("boom")
      def on_workitem_started(_ctx, _wi), do: throw(:noop)
    end

    test "no-op when handler is nil" do
      assert :ok = ActionHandler.safe_invoke(nil, :on_enactment_start, [%{}])
    end

    test "skips callback when handler doesn't export it" do
      assert :ok =
               ActionHandler.safe_invoke(SilentHandler, :on_workitem_completed, [%{}, %{}, %{}])
    end

    test "swallows raised exceptions" do
      assert :ok = ActionHandler.safe_invoke(CrashyHandler, :on_enactment_start, [%{}])
    end

    test "swallows thrown values" do
      assert :ok = ActionHandler.safe_invoke(CrashyHandler, :on_workitem_started, [%{}, %{}])
    end

    test "calls handler when callback is exported and well-behaved" do
      defmodule EchoHandler do
        @behaviour ActionHandler
        def on_enactment_start(ctx), do: send(self(), {:start_called, ctx})
      end

      ctx = %{enactment_id: "abc", markings: %{}}
      assert :ok = ActionHandler.safe_invoke(EchoHandler, :on_enactment_start, [ctx])
      assert_received {:start_called, ^ctx}
    end
  end

  describe "build_ctx/2" do
    test "extracts tokens from %Marking{} structs" do
      markings = %{
        "p1" => %Marking{place: "p1", tokens: MultiSet.new([1, 2, 3])},
        "p2" => %Marking{place: "p2", tokens: MultiSet.new([:a])}
      }

      ctx = ActionHandler.build_ctx("eid-1", markings)

      assert ctx.enactment_id == "eid-1"
      assert ctx.markings["p1"] == MultiSet.new([1, 2, 3])
      assert ctx.markings["p2"] == MultiSet.new([:a])
    end
  end
end
