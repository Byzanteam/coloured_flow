defmodule ColouredFlowDashboard.TelemetryBridge do
  @moduledoc """
  Attaches to every `[:coloured_flow, :runner, :enactment, *]` telemetry event
  produced by the `coloured_flow` runner and republishes them as
  `ColouredFlowDashboard.TelemetryBridge.Event` structs on `Phoenix.PubSub`.

  ## Topics

  Subscribers `Phoenix.PubSub.subscribe(:coloured_flow_dashboard_pubsub, topic)`
  receive `{:cf_event, %ColouredFlowDashboard.TelemetryBridge.Event{}}` messages.

    * `"cf:inbox"` — every workitem-shape or lifecycle change, regardless of
      enactment. Drives the operator inbox.
    * `"cf:enactment:<id>"` — every event scoped to a single enactment. Drives
      the detail page.
    * `"cf:flow:<module>"` — **deferred this phase.** The runner's
      `ColouredFlow.Runner.Enactment` struct does not carry a flow-module
      identity; only `enactment_id`. Resolving the flow module from the
      `enactment_id` requires a synchronous read against
      `ColouredFlow.Runner.Storage.get_flow_by_enactment/1`, which would
      defeat the "do not block the runner" rule and couple the bridge to
      the storage backend. A later phase must either thread the flow id
      through the runner's telemetry metadata (a main-repo change, off-limits
      to the dashboard epic) or maintain a side-channel `enactment_id ↦
      flow_module` map seeded by the dashboard's flow registry.

  ## Async invariant

  The handler runs inline with `:telemetry.execute/3` inside the runner
  GenServer. It MUST NOT block: it extracts the broadcast payload and hands
  it to `Task.Supervisor.start_child/2` against
  `ColouredFlowDashboard.TaskSupervisor`. The actual `Phoenix.PubSub.broadcast/3`
  runs in the task, off the runner's reduction budget.

  ## Catalog drift

  The list returned by `events/0` is the bridge's authoritative event catalog.
  A test asserts it equals an inline expectation matching
  `ColouredFlow.Runner.Telemetry.DefaultLogger`. When the main repo adds an
  event, that test fails and forces a sync here.
  """

  use GenServer

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.MultiSet
  alias ColouredFlow.Runner.Enactment, as: RunnerEnactment
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlowDashboard.TelemetryBridge.Event

  require Logger

  @handler_id __MODULE__
  @default_pubsub :coloured_flow_dashboard_pubsub
  @default_task_supervisor ColouredFlowDashboard.TaskSupervisor

  @enactment_lifecycle_events ~w[start stop terminate exception take_snapshot]a
  @workitem_operations ~w[produce_workitems start_workitems withdraw_workitems complete_workitems]a
  @workitem_op_events ~w[start stop exception]a

  @type option() ::
          {:name, GenServer.name()}
          | {:handler_id, :telemetry.handler_id()}
          | {:pubsub, atom()}
          | {:task_supervisor, atom()}

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the authoritative list of telemetry events this bridge attaches to.

  Kept in sync with `ColouredFlow.Runner.Telemetry.DefaultLogger`. Surfaced for
  the catalog drift test in `telemetry_bridge_test.exs`.
  """
  @spec events() :: [:telemetry.event_name()]
  def events do
    lifecycle =
      for event <- @enactment_lifecycle_events,
          do: [:coloured_flow, :runner, :enactment, event]

    workitem_ops =
      for op <- @workitem_operations,
          ev <- @workitem_op_events,
          do: [:coloured_flow, :runner, :enactment, op, ev]

    lifecycle ++ workitem_ops
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    handler_id = Keyword.get(opts, :handler_id, @handler_id)
    pubsub = Keyword.get(opts, :pubsub, @default_pubsub)
    task_supervisor = Keyword.get(opts, :task_supervisor, @default_task_supervisor)

    config = %{
      handler_id: handler_id,
      pubsub: pubsub,
      task_supervisor: task_supervisor
    }

    # Detach any stale handler from a previous instance (hot reload, crashed
    # bridge that never reached terminate, repeated test attach) so the new
    # attach below cannot collide with `{:error, :already_exists}`.
    :ok = detach(handler_id)

    :ok = :telemetry.attach_many(handler_id, events(), &__MODULE__.handle_event/4, config)

    {:ok, %{handler_id: handler_id}}
  end

  @impl GenServer
  def terminate(_reason, %{handler_id: handler_id}) do
    detach(handler_id)
    :ok
  end

  @doc false
  @spec detach(:telemetry.handler_id()) :: :ok
  def detach(handler_id) do
    case :telemetry.detach(handler_id) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  end

  @doc false
  @spec handle_event(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          map()
        ) :: :ok
  def handle_event(event_name, measurements, metadata, config) do
    case build_broadcasts(event_name, measurements, metadata) do
      [] ->
        :ok

      broadcasts ->
        Task.Supervisor.start_child(config.task_supervisor, fn ->
          deliver_broadcasts(config.pubsub, broadcasts)
        end)

        :ok
    end
  end

  defp deliver_broadcasts(pubsub, broadcasts) do
    Enum.each(broadcasts, fn {topic, event} ->
      Phoenix.PubSub.broadcast(pubsub, topic, {:cf_event, event})
    end)
  end

  @spec build_broadcasts(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata()
        ) :: [{String.t(), Event.t()}]
  defp build_broadcasts(
         [:coloured_flow, :runner, :enactment, lifecycle] = event_name,
         measurements,
         metadata
       )
       when lifecycle in @enactment_lifecycle_events do
    case Map.get(metadata, :enactment_state) do
      %RunnerEnactment{} = state ->
        kind = lifecycle_kind(lifecycle)
        payload = lifecycle_payload(lifecycle, metadata)

        broadcasts(state, kind, occurred_at(measurements), payload)

      _missing ->
        log_missing_state(event_name, metadata)
        []
    end
  end

  defp build_broadcasts(
         [:coloured_flow, :runner, :enactment, operation, op_event] = event_name,
         measurements,
         metadata
       )
       when operation in @workitem_operations and op_event in @workitem_op_events do
    case Map.get(metadata, :enactment_state) do
      %RunnerEnactment{} = state ->
        kind = workitem_kind(operation, op_event)
        payload = workitem_payload(operation, op_event, metadata)

        broadcasts(state, kind, occurred_at(measurements), payload)

      _missing ->
        log_missing_state(event_name, metadata)
        []
    end
  end

  defp build_broadcasts(_event_name, _measurements, _metadata), do: []

  # Compile-time atom tables keep the runtime kind lookup off the
  # `:erlang.binary_to_atom/2` path that credo flags as unsafe.
  for lifecycle <- @enactment_lifecycle_events do
    defp lifecycle_kind(unquote(lifecycle)), do: unquote(:"enactment_#{lifecycle}")
  end

  for op <- @workitem_operations, ev <- @workitem_op_events do
    defp workitem_kind(unquote(op), unquote(ev)), do: unquote(:"#{op}_#{ev}")
  end

  defp broadcasts(%RunnerEnactment{} = state, kind, occurred_at, payload) do
    common = %{
      kind: kind,
      enactment_id: state.enactment_id,
      enactment_version: state.version,
      occurred_at: occurred_at,
      payload: payload,
      markings_summary: markings_summary(state.markings),
      workitems_summary: workitems_summary(state.workitems)
    }

    [
      {"cf:inbox", struct!(Event, Map.put(common, :topic, :inbox))},
      {"cf:enactment:#{state.enactment_id}",
       struct!(Event, Map.put(common, :topic, {:enactment, state.enactment_id}))}
    ]
  end

  @spec occurred_at(:telemetry.event_measurements()) :: DateTime.t()
  defp occurred_at(measurements) do
    case Map.get(measurements, :system_time) do
      nil -> DateTime.utc_now()
      value when is_integer(value) -> DateTime.from_unix!(value, :native)
    end
  end

  defp lifecycle_payload(:start, _metadata), do: %{}

  defp lifecycle_payload(:stop, metadata),
    do: %{reason: Map.get(metadata, :reason)}

  defp lifecycle_payload(:terminate, metadata) do
    %{
      termination_type: Map.get(metadata, :termination_type),
      termination_message: Map.get(metadata, :termination_message)
    }
  end

  defp lifecycle_payload(:exception, metadata) do
    exception = Map.get(metadata, :exception)

    %{
      exception_reason: Map.get(metadata, :exception_reason),
      error_banner: format_exception(exception)
    }
  end

  defp lifecycle_payload(:take_snapshot, _metadata), do: %{}

  defp workitem_payload(operation, :start, metadata) do
    extra =
      case operation do
        :produce_workitems ->
          %{binding_elements: metadata |> Map.get(:binding_elements, []) |> Enum.to_list()}

        :complete_workitems ->
          %{
            workitem_ids: Map.get(metadata, :workitem_ids, []),
            workitem_id_and_outputs:
              metadata |> Map.get(:workitem_id_and_outputs, []) |> Map.new()
          }

        _other ->
          %{workitem_ids: Map.get(metadata, :workitem_ids, [])}
      end

    Map.put(extra, :operation, operation)
  end

  defp workitem_payload(operation, :stop, metadata) do
    %{operation: operation, workitems: Map.get(metadata, :workitems, [])}
  end

  defp workitem_payload(operation, :exception, metadata) do
    %{
      operation: operation,
      kind: Map.get(metadata, :kind),
      reason: inspect_safe(Map.get(metadata, :reason)),
      error_banner:
        format_exception_with_kind(
          Map.get(metadata, :kind),
          Map.get(metadata, :reason),
          Map.get(metadata, :stacktrace, [])
        )
    }
  end

  defp format_exception(exception) when is_exception(exception),
    do: Exception.format_banner(:error, exception)

  defp format_exception(_other), do: nil

  defp format_exception_with_kind(nil, _reason, _stacktrace), do: nil
  defp format_exception_with_kind(_kind, nil, _stacktrace), do: nil

  defp format_exception_with_kind(kind, reason, stacktrace) do
    Exception.format_banner(kind, reason, stacktrace)
  rescue
    _error -> inspect_safe(reason)
  end

  defp inspect_safe(nil), do: nil
  defp inspect_safe(value), do: inspect(value, limit: :infinity, printable_limit: :infinity)

  @spec markings_summary(RunnerEnactment.markings()) :: map()
  defp markings_summary(markings) when is_map(markings) do
    total =
      Enum.reduce(markings, 0, fn {_place, %Marking{tokens: tokens}}, acc ->
        acc + MultiSet.size(tokens)
      end)

    per_place =
      Map.new(markings, fn {place, %Marking{tokens: tokens}} ->
        {place, MultiSet.size(tokens)}
      end)

    %{place_count: map_size(markings), total_tokens: total, per_place: per_place}
  end

  @spec workitems_summary(RunnerEnactment.workitems()) :: map()
  defp workitems_summary(workitems) when is_map(workitems) do
    by_state =
      workitems
      |> Map.values()
      |> Enum.frequencies_by(fn %Workitem{state: state} -> state end)

    %{count: map_size(workitems), by_state: by_state}
  end

  defp log_missing_state(event_name, metadata) do
    Logger.debug(fn ->
      "[#{inspect(__MODULE__)}] dropping telemetry event #{inspect(event_name)}; " <>
        ":enactment_state absent from metadata keys " <>
        inspect(Map.keys(metadata))
    end)
  end
end
