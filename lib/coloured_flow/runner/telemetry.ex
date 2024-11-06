# credo:disable-for-this-file Credo.Check.Refactor.AppendSingleItem
defmodule ColouredFlow.Runner.Telemetry do
  @moduledoc """
  Telemetry integration for event metrics, logging and error reporting.

  ## Enactment workitem events

  `ColouredFlow.Runner` emits telemetry span events for the following workitem
  operations during running:

  - `[:coloured_flow, :runner, :enactment, :produce_workitems, :start | :stop | :exception]`
  - `[:coloured_flow, :runner, :enactment, :allocate_workitems, :start | :stop | :exception]`
  - `[:coloured_flow, :runner, :enactment, :start_workitems, :start | :stop | :exception]`
  - `[:coloured_flow, :runner, :enactment, :withdraw_workitems, :start | :stop | :exception]`
  - `[:coloured_flow, :runner, :enactment, :complete_workitems, :start | :stop | :exception]`

  All workitem events share the same measurements, but their metadata will differ
  a bit. In addition, `:exception` events will obey the `:telemetry.span/3`
  exception event format.

  | event        | measurements                      | metadata                                                               |
  | ------------ | --------------------------------- | ---------------------------------------------------------------------- |
  | `:start`     | `:system_time`, `:monotonic_time` | `:enactment_id`, `:enactment_state`, additional metadata (see below)   |
  | `:stop`      | `:duration`, `:monotonic_time`    | `:enactment_id`, `:enactment_state`                                    |
  | `:exception` | `:duration`, `:monotonic_time`    | `:enactment_id`, `:enactment_state`, `:kind`, `:reason`, `:stacktrace` |

  #### Metadata

  - `:enactment_id` — The ID of the running enactment.
  - `:enactment_state` — The current state of the enactment
  (`t:ColouredFlow.Runner.Enactment.state/0`).
  - `:workitems` — The workitems that were transitioned.

  #### Additional metadata

  The table below lists the additional metadata included in the workitem events:

  | event                 | start.metadata                              | stop.metadata |
  | --------------------- | ------------------------------------------- | ------------- |
  | `:produce_workitems`  | `:binding_elements`                         | `:workitems`  |
  | `:allocate_workitems` | `:workitem_ids`                             | `:workitems`  |
  | `:start_workitems`    | `:workitem_ids`                             | `:workitems`  |
  | `:withdraw_workitems` | `:workitem_ids`                             | `:workitems`  |
  | `:complete_workitems` | `:workitem_ids`, `:workitem_id_and_outputs` | `:workitems`  |
  """

  @type event_prefix() :: :telemetry.event_prefix()
  @type event_metadata() :: :telemetry.event_metadata()
  @type event_measurements() :: :telemetry.event_measurements()
  @type span_function(result, exception) ::
          (-> {:ok, result, event_metadata()})
          | (-> {:ok, result, event_measurements(), event_metadata()})
          | (-> {:error, exception})

  @doc """
  Start a telemetry span event and execute the given function. The function must return either
  `{:ok, result, metadata}`, `{:ok, result, measurements, metadata}` or `{:error, exception}`.
  If the function raises an exception, it will be caught and reported as an exception event.
  The returned result is different to the result of `:telemetry.span/3` as it only returns the
  `{:ok, result}` or `{:error, exception}` tuple.
  """
  @spec span(event_prefix(), event_metadata(), (-> {:ok, result, event_metadata()})) ::
          {:ok, result}
        when result: var
  @spec span(
          event_prefix(),
          event_metadata(),
          (-> {:ok, result, event_measurements(), event_metadata()})
        ) ::
          {:ok, result}
        when result: var
  @spec span(event_prefix(), event_metadata(), (-> {:error, exception})) ::
          {:error, exception}
        when exception: Exception.t()
  @spec span(
          event_prefix(),
          event_metadata(),
          (-> {:error, exception, Exception.stacktrace()})
        ) ::
          {:error, exception}
        when exception: Exception.t()
  def span(event_prefix, start_metadata, span_function)
      when is_list(event_prefix) and is_map(start_metadata) and is_function(span_function, 0) do
    start_time = System.monotonic_time()
    default_ctx = make_ref()

    :telemetry.execute(
      event_prefix ++ [:start],
      %{monotonic_time: start_time, system_time: System.system_time()},
      merge_ctx(start_metadata, %{}, default_ctx)
    )

    try do
      case span_function.() do
        {:ok, result, stop_metadata} ->
          :telemetry.execute(
            event_prefix ++ [:stop],
            include_duration(start_time, %{}),
            merge_ctx(stop_metadata, %{}, default_ctx)
          )

          {:ok, result}

        {:ok, result, extra_measurements, stop_metadata} ->
          :telemetry.execute(
            event_prefix ++ [:stop],
            include_duration(start_time, extra_measurements),
            merge_ctx(stop_metadata, %{}, default_ctx)
          )

          {:ok, result}

        {:error, exception} when is_exception(exception) ->
          :telemetry.execute(
            event_prefix ++ [:exception],
            include_duration(start_time, %{}),
            merge_ctx(
              start_metadata,
              %{kind: :error, reason: exception, stacktrace: []},
              default_ctx
            )
          )

          {:error, exception}

        {:error, exception, stacktrace} when is_exception(exception) ->
          :telemetry.execute(
            event_prefix ++ [:exception],
            include_duration(start_time, %{}),
            merge_ctx(
              start_metadata,
              %{kind: :error, reason: exception, stacktrace: stacktrace},
              default_ctx
            )
          )

          {:error, exception}
      end
    rescue
      exception ->
        :telemetry.execute(
          event_prefix ++ [:exception],
          include_duration(start_time, %{}),
          merge_ctx(
            start_metadata,
            %{kind: :error, reason: exception, stacktrace: __STACKTRACE__},
            default_ctx
          )
        )

        reraise exception, __STACKTRACE__
    catch
      kind, reason ->
        :telemetry.execute(
          event_prefix ++ [:exception],
          include_duration(start_time, %{}),
          merge_ctx(
            start_metadata,
            %{kind: kind, reason: reason, stacktrace: __STACKTRACE__},
            default_ctx
          )
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp merge_ctx(base_metadata, %{} = metadata, default_ctx),
    do: base_metadata |> Map.merge(metadata) |> Map.put_new(:telemetry_span_context, default_ctx)

  defp include_duration(start_time, measurements) do
    stop_time = System.monotonic_time()

    Map.merge(measurements, %{duration: stop_time - start_time, monotonic_time: stop_time})
  end
end
