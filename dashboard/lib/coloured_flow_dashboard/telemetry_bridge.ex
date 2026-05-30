defmodule ColouredFlowDashboard.TelemetryBridge do
  @moduledoc """
  Attaches to every `[:coloured_flow, :runner, :enactment, *]` telemetry event
  produced by the `coloured_flow` runner and republishes them as
  `ColouredFlowDashboard.TelemetryBridge.Event` structs on `Phoenix.PubSub`.

  ## Topics

  Subscribers `Phoenix.PubSub.subscribe(:coloured_flow_dashboard_pubsub, topic)`
  receive `{:cf_event, %ColouredFlowDashboard.TelemetryBridge.Event{}}` messages.
  Topic strings are prefixed with the bridge's `:topic_prefix` option
  (default `"cf:"`); the shapes below assume the default.

    * `"cf:inbox"` — every workitem-shape or lifecycle change, regardless of
      enactment. Drives the operator inbox.
    * `"cf:enactment:<id>"` — every event scoped to a single enactment. Drives
      the detail page.
    * `"cf:flow:<flow_id>"` — every event scoped to a single flow definition.
      `<flow_id>` is a stable string derived from the `%ColouredPetriNet{}`
      returned by `ColouredFlow.Runner.Storage.get_flow_by_enactment/1`. The
      runner only knows enactment ids — the public storage surface returns the
      flow's CPN definition (no Elixir module identity, no flow-row id). We
      therefore derive a stable id by hashing the cpnet term with
      `:erlang.phash2/1`; two enactments sharing the same flow definition share
      the same topic. If the storage backend later exposes a module/uuid
      identifier, swap `flow_topic_id/1` over.

  ## Async invariant

  The handler runs inline with `:telemetry.execute/3` inside the runner
  GenServer. It MUST NOT block: it hands `{event_name, measurements, metadata}`
  off to `Task.Supervisor.start_child/2` against the configured task supervisor
  and returns `:ok` immediately. ALL real work — event shaping, the storage
  read used to populate the flow cache, and `Phoenix.PubSub.broadcast/3` — runs
  inside that supervised task, off the runner's reduction budget.

  ## Flow cache

  Resolving the flow topic requires a storage read. To keep that off the
  runner AND off the hot path of repeat events for the same enactment, the
  bridge owns a small ETS table (`:set`, `:public`, `:named_table`) keyed by
  `enactment_id` and valued by `{flow_topic_id, %ColouredPetriNet{}}`. The
  cache is populated lazily on first hit inside the task body; the
  per-enactment flow is immutable so entries never expire. If the storage
  lookup fails (e.g. the enactment row hasn't been written yet, or the
  backend has no record), the task logs at `debug` and skips the `cf:flow:*`
  broadcast for that event; `cf:inbox` and `cf:enactment:<id>` are unaffected.

  Read-side consumers (e.g. `InboxStore`) reuse the same cache via
  `lookup_flow_topic_id/2` and `lookup_cpnet/2`. Both helpers populate the
  cache on miss, so the first row construction for an unseen enactment
  takes the storage hit; subsequent rows are served from ETS.

  ## Catalog drift

  The list returned by `events/0` is the bridge's authoritative event catalog.
  A test asserts it equals an inline expectation matching
  `ColouredFlow.Runner.Telemetry.DefaultLogger`. When the main repo adds an
  event, that test fails and forces a sync here.
  """

  use GenServer

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.MultiSet
  alias ColouredFlow.Runner.Enactment, as: RunnerEnactment
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Storage
  alias ColouredFlowDashboard.TelemetryBridge.Event

  require Logger

  @handler_id __MODULE__
  @default_pubsub :coloured_flow_dashboard_pubsub
  @default_task_supervisor ColouredFlowDashboard.TaskSupervisor
  @default_flow_cache :coloured_flow_dashboard_telemetry_bridge_flow_cache
  @default_topic_prefix "cf:"

  @enactment_lifecycle_events ~w[start stop terminate exception take_snapshot]a
  @workitem_operations ~w[produce_workitems start_workitems withdraw_workitems complete_workitems]a
  @workitem_op_events ~w[start stop exception]a

  @type broadcast_fn() :: (atom(), String.t(), term() -> :ok | {:error, term()})

  @type option() ::
          {:name, GenServer.name()}
          | {:handler_id, :telemetry.handler_id()}
          | {:pubsub, atom()}
          | {:task_supervisor, atom()}
          | {:topic_prefix, String.t()}
          | {:flow_cache, atom()}
          | {:broadcast_fn, broadcast_fn()}

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
    topic_prefix = Keyword.get(opts, :topic_prefix, @default_topic_prefix)
    flow_cache = Keyword.get(opts, :flow_cache, @default_flow_cache)
    broadcast_fn = Keyword.get(opts, :broadcast_fn, &Phoenix.PubSub.broadcast/3)

    # GenServer owns the ETS table so it dies with us (test cleanup is free).
    # `:public` lets the Task.Supervisor child write to it without going
    # through the GenServer.
    flow_cache = ensure_table(flow_cache)

    config = %{
      handler_id: handler_id,
      pubsub: pubsub,
      task_supervisor: task_supervisor,
      topic_prefix: topic_prefix,
      flow_cache: flow_cache,
      broadcast_fn: broadcast_fn
    }

    # Detach any stale handler from a previous instance (hot reload, crashed
    # bridge that never reached terminate, repeated test attach) so the new
    # attach below cannot collide with `{:error, :already_exists}`.
    :ok = detach(handler_id)

    :ok = :telemetry.attach_many(handler_id, events(), &__MODULE__.handle_event/4, config)

    {:ok, %{handler_id: handler_id, flow_cache: flow_cache}}
  end

  defp ensure_table(name) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, [
          :set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])

      _existing ->
        name
    end
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
    # Defer EVERYTHING — shaping, flow lookup, broadcast — to the task. The
    # only work that runs inline with the runner's `:telemetry.execute/3` is
    # the `start_child` call AND the `allocate_seq/1` monotonic bump. Tests
    # assert async-ness by injecting a blocking `:broadcast_fn`; the seq
    # bump is a bounded-time VM call so it preserves the invariant.
    seq = allocate_seq(metadata)

    Task.Supervisor.start_child(config.task_supervisor, fn ->
      dispatch(event_name, measurements, metadata, seq, config)
    end)

    :ok
  end

  # `seq` is a VM-wide strictly-increasing integer. Allocating it inline
  # (before the task fans out) means two events are stamped in the runner's
  # serialized telemetry order even if their tasks then race; per-enactment
  # ordering is preserved because `:telemetry.execute/3` runs in the
  # runner's calling-process context. `System.unique_integer/1` survives
  # any bridge restart / supervisor restart / code reload — a freshly
  # rebooted bridge cannot regress consumers' accumulated `last_seq`. When
  # `enactment_id` is missing the event is unscoped — return `0`; such
  # events drop in `build_broadcasts/4` anyway.
  defp allocate_seq(metadata) do
    case enactment_id_from_metadata(metadata) do
      nil -> 0
      _eid -> System.unique_integer([:monotonic, :positive])
    end
  end

  defp enactment_id_from_metadata(metadata) do
    case Map.get(metadata, :enactment_state) do
      %RunnerEnactment{enactment_id: eid} ->
        eid

      _other ->
        case Map.get(metadata, :enactment_id) do
          eid when is_binary(eid) -> eid
          _missing -> nil
        end
    end
  end

  defp dispatch(event_name, measurements, metadata, seq, config) do
    case build_broadcasts(event_name, measurements, metadata, seq, config) do
      [] -> :ok
      broadcasts -> deliver_broadcasts(config, broadcasts)
    end
  end

  defp deliver_broadcasts(config, broadcasts) do
    Enum.each(broadcasts, fn {topic, event} ->
      config.broadcast_fn.(config.pubsub, topic, {:cf_event, event})
    end)
  end

  @spec build_broadcasts(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          pos_integer(),
          map()
        ) :: [{String.t(), Event.t()}]
  defp build_broadcasts(
         [:coloured_flow, :runner, :enactment, lifecycle] = event_name,
         measurements,
         metadata,
         seq,
         config
       )
       when lifecycle in @enactment_lifecycle_events do
    case Map.get(metadata, :enactment_state) do
      %RunnerEnactment{} = state ->
        kind = lifecycle_kind(lifecycle)
        payload = lifecycle_payload(lifecycle, metadata)

        broadcasts(state, kind, occurred_at(measurements), payload, seq, config)

      _missing ->
        log_missing_state(event_name, metadata)
        []
    end
  end

  defp build_broadcasts(
         [:coloured_flow, :runner, :enactment, operation, op_event] = event_name,
         measurements,
         metadata,
         seq,
         config
       )
       when operation in @workitem_operations and op_event in @workitem_op_events do
    case Map.get(metadata, :enactment_state) do
      %RunnerEnactment{} = state ->
        kind = workitem_kind(operation, op_event)
        payload = workitem_payload(operation, op_event, metadata)

        broadcasts(state, kind, occurred_at(measurements), payload, seq, config)

      _missing ->
        log_missing_state(event_name, metadata)
        []
    end
  end

  defp build_broadcasts(_event_name, _measurements, _metadata, _seq, _config), do: []

  # Compile-time atom tables keep the runtime kind lookup off the
  # `:erlang.binary_to_atom/2` path that credo flags as unsafe.
  for lifecycle <- @enactment_lifecycle_events do
    defp lifecycle_kind(unquote(lifecycle)), do: unquote(:"enactment_#{lifecycle}")
  end

  for op <- @workitem_operations, ev <- @workitem_op_events do
    defp workitem_kind(unquote(op), unquote(ev)), do: unquote(:"#{op}_#{ev}")
  end

  defp broadcasts(%RunnerEnactment{} = state, kind, occurred_at, payload, seq, config) do
    common = %{
      kind: kind,
      enactment_id: state.enactment_id,
      enactment_version: state.version,
      seq: seq,
      occurred_at: occurred_at,
      payload: payload,
      markings_summary: markings_summary(state.markings),
      workitems_summary: workitems_summary(state.workitems)
    }

    prefix = config.topic_prefix

    base = [
      {"#{prefix}inbox", struct!(Event, Map.put(common, :topic, :inbox))},
      {"#{prefix}enactment:#{state.enactment_id}",
       struct!(Event, Map.put(common, :topic, {:enactment, state.enactment_id}))}
    ]

    case lookup_flow_topic_id(state.enactment_id, config.flow_cache) do
      {:ok, flow_id} ->
        flow_topic =
          {"#{prefix}flow:#{flow_id}", struct!(Event, Map.put(common, :topic, {:flow, flow_id}))}

        [flow_topic | base]

      :error ->
        base
    end
  end

  @doc """
  Looks up (or resolves and caches) the flow topic id for an enactment.

  Public so the `task_supervisor`-spawned task can call into it; tests may
  also pre-warm the cache. Returns `{:ok, flow_id}` on success, `:error`
  when the storage lookup fails (and skips the `cf:flow:*` topic for that
  event family).
  """
  @spec lookup_flow_topic_id(Event.enactment_id(), atom()) :: {:ok, String.t()} | :error
  def lookup_flow_topic_id(enactment_id, cache) do
    case lookup_cached(enactment_id, cache) do
      {:ok, {flow_id, _cpnet}} -> {:ok, flow_id}
      :error -> :error
    end
  end

  @doc """
  Looks up (or resolves and caches) the `%ColouredPetriNet{}` definition for
  an enactment. Shares the same fetch + ETS cache as `lookup_flow_topic_id/2`.

  Used by `ColouredFlowDashboardWeb.Stores.InboxStore` to derive the
  transition's free-variable list (`output_vars`) for the outputs drawer.
  Returns `:error` when storage has no flow for the enactment (e.g. the row
  is gone or the in-memory store is uninitialised). Callers MUST tolerate
  `:error` and surface an empty hint to the operator.
  """
  @spec lookup_cpnet(Event.enactment_id(), atom()) :: {:ok, ColouredPetriNet.t()} | :error
  def lookup_cpnet(enactment_id, cache) do
    case lookup_cached(enactment_id, cache) do
      {:ok, {_flow_id, cpnet}} -> {:ok, cpnet}
      :error -> :error
    end
  end

  defp lookup_cached(enactment_id, cache) do
    case :ets.lookup(cache, enactment_id) do
      [{^enactment_id, flow_id, %ColouredPetriNet{} = cpnet}] ->
        {:ok, {flow_id, cpnet}}

      [] ->
        resolve_and_cache(enactment_id, cache)
    end
  end

  defp resolve_and_cache(enactment_id, cache) do
    case fetch_flow(enactment_id) do
      {:ok, %ColouredPetriNet{} = cpnet} ->
        flow_id = flow_topic_id(cpnet)
        :ets.insert(cache, {enactment_id, flow_id, cpnet})
        {:ok, {flow_id, cpnet}}

      :error ->
        :error
    end
  end

  defp fetch_flow(enactment_id) do
    {:ok, Storage.get_flow_by_enactment(enactment_id)}
  catch
    kind, reason ->
      Logger.debug(fn ->
        "[#{inspect(__MODULE__)}] flow lookup failed for enactment #{inspect(enactment_id)}: " <>
          Exception.format(kind, reason, __STACKTRACE__)
      end)

      :error
  end

  @doc """
  Derives the stable `cf:flow:<id>` topic suffix for a coloured petri net
  definition. Two enactments backed by the same `%ColouredPetriNet{}` share
  the same topic. The storage backend returns no module/uuid identity through
  its public surface, so the bridge hashes the term itself.
  """
  @spec flow_topic_id(ColouredPetriNet.t()) :: String.t()
  def flow_topic_id(%ColouredPetriNet{} = cpnet),
    do: Integer.to_string(:erlang.phash2(cpnet))

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
