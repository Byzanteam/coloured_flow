# credo:disable-for-this-file Credo.Check.Refactor.AppendSingleItem
defmodule ColouredFlow.Runner.TelemetryTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Runner.Telemetry

  describe "span/3" do
    setup :attach_event_handlers

    @tag event_name: [:ok, :result, :event_metadata]
    test "{:ok, result, event_metadata()}",
         %{
           event_name: event_name,
           start_event_name: start_event_name,
           stop_event_name: stop_event_name,
           handler_id: handler_id
         } do
      assert {:ok, :result} =
               Telemetry.span(
                 event_name,
                 %{foo: :bar},
                 fn -> {:ok, :result, %{foo: :baz}} end
               )

      assert_received {
        ^start_event_name,
        ^handler_id,
        %{monotonic_time: _, system_time: _},
        %{foo: :bar}
      }

      assert_received {
        ^stop_event_name,
        ^handler_id,
        %{monotonic_time: _, duration: _},
        %{foo: :baz}
      }
    end

    @tag event_name: [:ok, :result, :event_measurements, :event_metadata]
    test "{:ok, result, event_measurements(), event_metadata()}",
         %{
           event_name: event_name,
           start_event_name: start_event_name,
           stop_event_name: stop_event_name,
           handler_id: handler_id
         } do
      assert {:ok, :result} =
               Telemetry.span(
                 event_name,
                 %{foo: :bar},
                 fn -> {:ok, :result, %{latency: 100}, %{foo: :baz}} end
               )

      assert_received {
        ^start_event_name,
        ^handler_id,
        %{monotonic_time: _, system_time: _},
        %{foo: :bar}
      }

      assert_received {
        ^stop_event_name,
        ^handler_id,
        %{monotonic_time: _, duration: _, latency: 100},
        %{foo: :baz}
      }
    end

    @tag event_name: [:error, :exception]
    test "{:error, exception}", %{
      event_name: event_name,
      start_event_name: start_event_name,
      exception_event_name: exception_event_name,
      handler_id: handler_id
    } do
      exception = RuntimeError.exception("oops!")

      assert {:error, ^exception} =
               Telemetry.span(
                 event_name,
                 %{foo: :bar},
                 fn -> {:error, exception} end
               )

      assert_received {
        ^start_event_name,
        ^handler_id,
        %{monotonic_time: _, system_time: _},
        %{foo: :bar}
      }

      assert_received {
        ^exception_event_name,
        ^handler_id,
        %{monotonic_time: _, duration: _},
        %{foo: :bar, kind: :error, reason: ^exception}
      }
    end

    @tag event_name: [:exception]
    test "exception", %{
      event_name: event_name,
      start_event_name: start_event_name,
      exception_event_name: exception_event_name,
      handler_id: handler_id
    } do
      exception = RuntimeError.exception("oops!")

      assert_raise RuntimeError, "oops!", fn ->
        Telemetry.span(
          event_name,
          %{foo: :bar},
          fn -> raise exception end
        )
      end

      assert_received {
        ^start_event_name,
        ^handler_id,
        %{monotonic_time: _, system_time: _},
        %{foo: :bar}
      }

      assert_received {
        ^exception_event_name,
        ^handler_id,
        %{monotonic_time: _, duration: _},
        %{foo: :bar, kind: :error, reason: ^exception}
      }
    end
  end

  defp attach_event_handlers(%{event_name: event_name}) do
    start_event_name = event_name ++ [:start]
    stop_event_name = event_name ++ [:stop]
    exception_event_name = event_name ++ [:exception]

    handler_id =
      :telemetry_test.attach_event_handlers(self(), [
        start_event_name,
        stop_event_name,
        exception_event_name
      ])

    on_exit(fn -> :telemetry.detach(handler_id) end)

    [
      start_event_name: start_event_name,
      stop_event_name: stop_event_name,
      exception_event_name: exception_event_name,
      handler_id: handler_id
    ]
  end
end
