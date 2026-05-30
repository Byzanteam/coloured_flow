defmodule ColouredFlowDashboardWeb.Stores.EnactmentDetailStore do
  @moduledoc """
  Root Musubi store backing the per-enactment detail page at
  `/enactments/:id`. Mounted from the SPA via:

      useMusubiRootSuspense({
        module: "ColouredFlowDashboardWeb.Stores.EnactmentDetailStore",
        id: enactmentId,
        params: { id: enactmentId }
      })

  The `id` arg is propagated as `params["id"]` because Musubi's
  `mountStore({ module, id })` does not auto-thread the store id into
  `mount/2`'s `params` map — only the explicit `params` object reaches the
  server.

  ## State

    * `summary` — a `ColouredFlowDashboardWeb.Views.EnactmentSummary` rollup.
    * `transitions` — sorted list of transition names declared by the cpnet
      backing this enactment. Empty when the bridge cache cannot resolve a
      cpnet (e.g. enactment row not yet written). Drives the Debug tab's
      transition picker.
    * `:markings` stream — `MarkingRow` per place, keyed by `place` name.
    * `:workitems` stream — `WorkitemRow` per live workitem (same Wire shape
      used by `InboxStore`), keyed by workitem id.
    * `:occurrences` stream — `OccurrenceRow` per fired occurrence, keyed by
      the synthetic `"<enactment_id>-<step_number>"` id. The `step_number`
      field is a per-mount stable index — the SPA surfaces it as a
      "Position" column to avoid implying a stable cross-session identifier.
      Capped to 200 rows.
    * `:telemetry` stream — `TelemetryEntry` per bridge event matching this
      enactment. Capped to 100 rows; the stream limit drops oldest entries
      automatically. Bridge events do not carry per-event ids, so the store
      mints `"<enactment_id>-<unique>"` at insert time via a monotonic
      counter.

  ## Event routing

  Subscribes to `"cf:enactment:<id>"`. Routing by `Event.kind`:

  | kind                          | action                                                                                          |
  | ----------------------------- | ----------------------------------------------------------------------------------------------- |
  | `:produce_workitems_stop`     | upsert into `:workitems`; bump summary.workitems_count + version                                |
  | `:start_workitems_stop`       | upsert into `:workitems` (`:enabled → :started`)                                                |
  | `:withdraw_workitems_stop`    | delete from `:workitems`                                                                        |
  | `:complete_workitems_stop`    | delete from `:workitems`; insert into `:occurrences` (one per workitem); set last_occurrence_at |
  | `:enactment_take_snapshot`    | bump summary.version                                                                            |
  | `:enactment_terminate`        | summary.state = `:terminated`; flush remaining workitem rows; clear last_exception_banner       |
  | `:enactment_exception`        | summary.state = `:exception`; set last_exception_banner from payload.error_banner               |
  | `:enactment_start`            | summary.state = `:running`; refresh summary.version                                             |
  | everything else               | no-op (`*_workitems_start`, `:enactment_stop`, exception halves)                                |

  Cross-enactment events are filtered out via `event.enactment_id` so the
  store ignores any topic-level crosstalk.

  ## Marking refresh

  The bridge payload does not carry post-event markings. Rather than
  duplicate the runner's multiset arithmetic on the dashboard side, the
  store schedules a bounded `peek_live_enactment/1` round-trip after every
  firing event (`:complete_workitems_stop`, `:enactment_terminate`) and
  rebuilds the `:markings` stream from the runner's authoritative state
  (live runner GenServer → storage snapshot+replay fallback — same path as
  the mount-time seed).

  Concurrent fires are coalesced: a `marking_refresh_pending` flag gates
  the deferred `:refresh_markings` self-message so a burst of fires queues
  exactly one refresh. The dedupe relies on the per-enactment monotonic
  `event.seq` that the bridge stamps inside the runner's
  `:telemetry.execute/3` — stale events are dropped before they can
  schedule a refresh.

  ## Storage / runner peek strategy

  `seed_world/1` first tries to read the live runner GenServer state, then
  falls back to `Storage.read_enactment_snapshot/1` + `CatchingUp.apply/2`.
  Live-peek failures (including the bounded-timeout case) log at
  `:debug` and route to the storage fallback path.

  ## Reliance on private runner surfaces

  M3a intentionally reaches into a few internal runner surfaces because the
  main repo does not yet expose a public read API for live enactment state.
  The dashboard never mutates through these surfaces:

    * `ColouredFlow.Runner.Enactment` GenServer is read via
      `:sys.get_state/2` (OTP debugging API) with a bounded 500 ms timeout
      to avoid blocking the page mount.
    * `ColouredFlow.Runner.Enactment.Registry` is `@moduledoc false` in the
      main repo and is used here only as a `whereis` source for the live
      enactment pid.
    * `ColouredFlow.Runner.Storage.read_enactment_snapshot/1` +
      `ColouredFlow.Runner.Enactment.CatchingUp.apply/2` provide the
      fallback path for terminated or temporarily unreachable enactments.

  These choices preserve the zero-main-change rule (see epic plan). If the
  main repo later exposes a proper `Runner.Enactment.peek/1` (or
  equivalent) public surface, swap to it and drop the `:sys.get_state`
  reliance here.

  ## Commands

    * `:force_terminate` — `Runner.Enactment.Supervisor.terminate_enactment/2`
      with the operator-supplied `:message`. Reply codes:
      `:ok | :already_terminated | :runner_error`.
    * `:take_snapshot` — sends a `:take_snapshot` message to the enactment
      GenServer (same hot path the runner uses internally after completions).
      Reply codes: `:ok | :not_running | :runner_error`.
    * `:retry_enactment` — combines two public main-repo surfaces to recover an
      `:exception`-state enactment: `Storage.retry_enactment/2` flips the DB
      row back to `:running` and writes a `:retried` log entry; then
      `Runner.Enactment.Supervisor.start_enactment/1` brings the GenServer
      back online (the supervisor returns `{:ok, pid}` for both fresh starts
      and `:already_started`). Reply codes:
      `:ok | :not_exception | :already_terminated | :runner_error`. The
      command rejects when the dashboard's current `summary.state` is not
      `:exception` so an operator can't toggle a healthy enactment off the
      hot path.
    * `:inspect_transition` — read-only enumeration of candidate bindings
      for a single transition, delegating to
      `ColouredFlowDashboard.BindingInspector.inspect/3`. Reply codes:
      `:ok | :unknown_transition | :cpnet_unavailable`. The `:ok` reply
      carries `info :: TransitionDebugInfo.t()` and
      `candidates :: [BindingCandidate.t()]` — both pre-rendered for the
      SPA wire so the Debug tab does not need its own decoder.
  """

  use Musubi.Store, root: true

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.MultiSet
  alias ColouredFlow.Runner
  alias ColouredFlow.Runner.Enactment, as: RunnerEnactment
  alias ColouredFlow.Runner.Enactment.CatchingUp
  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Enactment.Workitem, as: RunnerWorkitem
  alias ColouredFlow.Runner.Storage
  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlow.Runner.Worklist.WorkitemStream
  alias ColouredFlowDashboard.BindingInspector
  alias ColouredFlowDashboard.ColourSetSummary
  alias ColouredFlowDashboard.OutputSchemaBuilder
  alias ColouredFlowDashboard.TelemetryBridge
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboard.WorkitemCompletion
  alias ColouredFlowDashboardWeb.Views.BindingCandidate
  alias ColouredFlowDashboardWeb.Views.BindingPair
  alias ColouredFlowDashboardWeb.Views.EnactmentSummary
  alias ColouredFlowDashboardWeb.Views.MarkingRow
  alias ColouredFlowDashboardWeb.Views.NetDiagram
  alias ColouredFlowDashboardWeb.Views.NetDiagramArc
  alias ColouredFlowDashboardWeb.Views.NetDiagramPlace
  alias ColouredFlowDashboardWeb.Views.NetDiagramTransition
  alias ColouredFlowDashboardWeb.Views.OccurrenceRow
  alias ColouredFlowDashboardWeb.Views.ReplayState
  alias ColouredFlowDashboardWeb.Views.TelemetryEntry
  alias ColouredFlowDashboardWeb.Views.TransitionDebugInfo
  alias ColouredFlowDashboardWeb.Views.VersionRange
  alias ColouredFlowDashboardWeb.Views.WorkitemRow

  import Ecto.Query, only: [from: 2, where: 3]

  require Logger

  @default_pubsub :coloured_flow_dashboard_pubsub
  @default_topic_prefix "cf:"
  @default_flow_cache :coloured_flow_dashboard_telemetry_bridge_flow_cache
  @occurrence_limit 200
  @workitem_limit 200
  @telemetry_limit 100
  @live_states RunnerWorkitem.__live_states__()
  # Bounded ceiling for the mount-time `:sys.get_state/2` peek so a slow or
  # stuck runner GenServer never blocks the page mount past this. On
  # timeout we fall through to the snapshot+replay path.
  @peek_timeout_ms 500
  # Coalescing delay for the post-fire live marking refresh. A burst of
  # firings within this window queues exactly one `peek_live_enactment/1`
  # round-trip because `marking_refresh_pending` gates the schedule.
  @marking_refresh_delay_ms 50

  # Musubi's `state do` type walker resolves `Mod.t()` against the host
  # module's namespace ancestry, not its `alias` table. Inline FQN refs.
  state do
    field :summary, ColouredFlowDashboardWeb.Views.EnactmentSummary.t()
    field :transitions, list(String.t())
    field :diagram, ColouredFlowDashboardWeb.Views.NetDiagram.t()

    stream :markings, ColouredFlowDashboardWeb.Views.MarkingRow.t(),
      limit: @workitem_limit,
      item_key: & &1.place

    stream :workitems, ColouredFlowDashboardWeb.Views.WorkitemRow.t(),
      limit: @workitem_limit,
      item_key: & &1.id

    stream :occurrences, ColouredFlowDashboardWeb.Views.OccurrenceRow.t(),
      limit: @occurrence_limit,
      item_key: & &1.id

    stream :telemetry, ColouredFlowDashboardWeb.Views.TelemetryEntry.t(),
      limit: @telemetry_limit,
      item_key: & &1.id
  end

  command :force_terminate do
    payload do
      field :reason, String.t()
    end

    reply do
      field :code, :ok | :already_terminated | :runner_error
    end
  end

  command :take_snapshot do
    reply do
      field :code, :ok | :not_running | :runner_error
    end
  end

  command :retry_enactment do
    reply do
      field :code, :ok | :not_exception | :already_terminated | :runner_error
    end
  end

  command :inspect_transition do
    payload do
      field :transition, String.t()
    end

    reply do
      field :code, :ok | :unknown_transition | :cpnet_unavailable
      field :info, ColouredFlowDashboardWeb.Views.TransitionDebugInfo.t() | nil
      field :candidates, list(ColouredFlowDashboardWeb.Views.BindingCandidate.t())
      field :transition, String.t() | nil
    end
  end

  # M7a — read-only derivation of a marking snapshot at a prior version.
  #
  # The handler reads the nearest snapshot ≤ requested version via
  # `Storage.read_enactment_snapshot/1` and replays `Storage.occurrences_stream/2`
  # through `CatchingUp.apply/2`, taking only the prefix up to the requested
  # version. The live `Runner.Enactment` GenServer is NOT touched — there are
  # no mutations on either the runner process or the persisted state.
  command :replay_to_version do
    payload do
      field :version, integer()
    end

    reply do
      field :code, :ok | :invalid_version | :runner_error
      field :markings, list(ColouredFlowDashboardWeb.Views.MarkingRow.t())
      field :replay_state, ColouredFlowDashboardWeb.Views.ReplayState.t() | nil
      field :available_max_version, integer() | nil
      field :snapshot_floor, integer() | nil
    end
  end

  command :exit_replay do
    reply do
      field :code, :ok
    end
  end

  # Mirrors `InboxStore`'s `:complete_workitem`. Reply codes are kept in
  # lockstep via `ColouredFlowDashboard.WorkitemCompletion`.
  command :complete_workitem do
    payload do
      field :workitem_id, String.t()
      field :outputs, map()
    end

    reply do
      field :code,
            :ok
            | :already_completed
            | :unknown_workitem
            | :unknown_variable
            | :invalid_outputs
            | :type_mismatch
            | :invalid_elixir
            | :runner_error
    end
  end

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  @impl Musubi.Store
  def mount(params, socket) when is_map(params) do
    enactment_id = Map.fetch!(params, "id")
    pubsub = Map.get(params, "pubsub_name", @default_pubsub)
    topic_prefix = Map.get(params, "topic_prefix", @default_topic_prefix)
    flow_cache = Map.get(params, "flow_cache", @default_flow_cache)
    topic = Map.get(params, "topic", "#{topic_prefix}enactment:#{enactment_id}")

    :ok = Phoenix.PubSub.subscribe(pubsub, topic)

    %{
      markings: markings,
      workitems: workitems,
      occurrences: occurrences,
      version: version,
      state: state_kind
    } = seed_world(enactment_id)

    flow_topic_id = resolve_flow_topic_id(enactment_id, flow_cache)
    flow_name = resolve_flow_name(enactment_id, flow_cache)
    transitions = resolve_transitions(enactment_id, flow_cache)
    last_occurrence_at = last_occurrence_at(occurrences)
    marking_index = build_marking_index(markings)
    enabled_workitems = seed_enabled_workitems(workitems)
    diagram = build_diagram(enactment_id, flow_cache, marking_index, enabled_workitems, %{})
    cpnet = cached_cpnet(enactment_id, flow_cache)
    workitems = Enum.map(workitems, &stamp_output_vars(&1, cpnet))
    workitem_meta = build_workitem_meta(workitems, enactment_id)

    # `min: 0` is invariant — the dashboard always reconstructs v0 (the
    # initial marking, BEFORE any occurrence fires) by replaying zero
    # occurrences against `Storage.get_initial_markings/1`. The persisted
    # snapshot floor is unrelated to scrubbing reach; for any target
    # < snapshot_version, `derive_replay/2` bypasses the snapshot and
    # replays from initial markings instead.
    summary = %EnactmentSummary{
      enactment_id: enactment_id,
      flow_topic_id: flow_topic_id,
      flow_name: flow_name,
      state: state_kind,
      version: version,
      markings_count: length(markings),
      workitems_count: length(workitems),
      last_occurrence_at: last_occurrence_at,
      last_exception_banner: nil,
      replay_state: nil,
      version_range: %VersionRange{min: 0, max: max(version, 0)}
    }

    socket =
      socket
      |> assign(:enactment_id, enactment_id)
      |> assign(:pubsub_name, pubsub)
      |> assign(:topic, topic)
      |> assign(:flow_cache, flow_cache)
      |> assign(:summary, summary)
      |> assign(:transitions, transitions)
      |> assign(:diagram, diagram)
      |> assign(:marking_index, marking_index)
      |> assign(:replay_marking_index, nil)
      |> assign(:enabled_workitems, enabled_workitems)
      |> assign(:transition_fired_at, %{})
      |> assign(:last_seq, 0)
      |> assign(:marking_refresh_pending, false)
      |> assign(:workitem_ids, MapSet.new(Enum.map(workitems, & &1.id)))
      |> assign(:workitem_meta, workitem_meta)
      |> stream(:markings, markings, reset: true)
      |> stream(:workitems, workitems, reset: true)
      |> stream(:occurrences, occurrences, reset: true)
      |> stream(:telemetry, [], reset: true)

    {:ok, socket}
  end

  @impl Musubi.Store
  def render(socket) do
    %{
      summary: socket.assigns.summary,
      transitions: socket.assigns.transitions,
      diagram: socket.assigns.diagram,
      markings: stream(:markings),
      workitems: stream(:workitems),
      occurrences: stream(:occurrences),
      telemetry: stream(:telemetry)
    }
  end

  # ---------------------------------------------------------------------------
  # Mailbox
  # ---------------------------------------------------------------------------

  @impl Musubi.Store
  def handle_info({:cf_event, %Event{} = event}, socket) do
    cond do
      event.enactment_id != socket.assigns.enactment_id ->
        {:noreply, socket}

      # Per-enactment monotonic seq stamped by `TelemetryBridge` inside the
      # runner's serialized `:telemetry.execute/3` call. Tasks may then
      # reorder during fan-out; a late `produce_workitems_stop` arriving
      # after `complete_workitems_stop` for the same enactment would
      # otherwise resurrect a finished workitem and roll `summary.version`
      # backward. Drop stale events here.
      stale?(event, socket) ->
        {:noreply, socket}

      true ->
        socket =
          socket
          |> bump_last_seq(event)
          |> then(&route_event(event, &1))
          |> append_telemetry(event)
          |> maybe_refresh_transitions()
          |> apply_diagram_event(event)
          |> refresh_diagram()
          |> maybe_schedule_marking_refresh(event)

        {:noreply, socket}
    end
  end

  def handle_info(:refresh_markings, socket) do
    socket =
      socket
      |> assign(:marking_refresh_pending, false)
      |> refresh_markings_now()
      |> refresh_diagram()

    {:noreply, socket}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp stale?(%Event{seq: seq}, socket) when is_integer(seq) and seq > 0,
    do: seq <= socket.assigns.last_seq

  defp stale?(%Event{}, _socket), do: false

  defp bump_last_seq(socket, %Event{seq: seq}) when is_integer(seq) and seq > 0,
    do: assign(socket, :last_seq, seq)

  defp bump_last_seq(socket, %Event{}), do: socket

  # ---------------------------------------------------------------------------
  # Commands
  # ---------------------------------------------------------------------------

  @impl Musubi.Store
  def handle_command(:force_terminate, payload, socket) when is_map(payload) do
    reason = Map.get(payload, "reason") || Map.get(payload, :reason) || ""
    {:reply, force_terminate_reply(socket.assigns.enactment_id, reason), socket}
  end

  def handle_command(:take_snapshot, _payload, socket) do
    {:reply, take_snapshot_reply(socket.assigns.enactment_id), socket}
  end

  def handle_command(:retry_enactment, _payload, socket) do
    {:reply, retry_enactment_reply(socket.assigns.enactment_id), socket}
  end

  def handle_command(:inspect_transition, payload, socket) when is_map(payload) do
    transition = Map.get(payload, "transition") || Map.get(payload, :transition) || ""
    {:reply, inspect_transition_reply(socket, transition), socket}
  end

  def handle_command(:replay_to_version, payload, socket) when is_map(payload) do
    version_raw = Map.get(payload, "version") || Map.get(payload, :version)

    case coerce_version(version_raw) do
      {:ok, version} ->
        case derive_replay(socket, version) do
          {:ok, marking_rows, replay_state, marking_index} ->
            socket =
              socket
              |> assign(:replay_marking_index, marking_index)
              |> put_replay_state(replay_state)
              |> refresh_diagram()

            reply = %{
              code: :ok,
              markings: marking_rows,
              replay_state: replay_state,
              available_max_version: socket.assigns.summary.version_range.max,
              snapshot_floor: current_snapshot_floor(socket.assigns.enactment_id)
            }

            {:reply, reply, socket}

          {:error, reason, info} ->
            reply =
              Map.merge(
                %{code: :invalid_version, markings: [], replay_state: nil},
                replay_error_fields(reason, info, socket)
              )

            {:reply, reply, socket}
        end

      :error ->
        reply = %{
          code: :invalid_version,
          markings: [],
          replay_state: nil,
          available_max_version: socket.assigns.summary.version_range.max,
          snapshot_floor: current_snapshot_floor(socket.assigns.enactment_id)
        }

        {:reply, reply, socket}
    end
  end

  def handle_command(:exit_replay, _payload, socket) do
    socket =
      socket
      |> assign(:replay_marking_index, nil)
      |> put_replay_state(nil)
      |> refresh_diagram()

    {:reply, %{code: :ok}, socket}
  end

  def handle_command(:complete_workitem, payload, socket) when is_map(payload) do
    workitem_id = Map.get(payload, "workitem_id") || Map.get(payload, :workitem_id)
    outputs_json = Map.get(payload, "outputs") || Map.get(payload, :outputs)
    meta = workitem_meta_for(socket, workitem_id)

    {:reply, WorkitemCompletion.complete(meta, workitem_id, outputs_json), socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}

  defp workitem_meta_for(socket, workitem_id) when is_binary(workitem_id) do
    Map.get(socket.assigns.workitem_meta, workitem_id)
  end

  defp workitem_meta_for(_socket, _workitem_id), do: nil

  # ---------------------------------------------------------------------------
  # Seed
  # ---------------------------------------------------------------------------

  defp seed_world(enactment_id) do
    case peek_live_enactment(enactment_id) do
      {:ok, %RunnerEnactment{} = state} ->
        %{
          markings: state.markings |> Map.values() |> Enum.map(&marking_row/1),
          workitems: state.workitems |> Map.values() |> Enum.map(&workitem_row(&1, enactment_id)),
          occurrences: seed_occurrences(enactment_id),
          version: state.version,
          # A live GenServer does NOT imply `:running`. The runner row can be
          # `:exception` (crash-threshold flip) while a pid still answers
          # `:sys.get_state/2` between exception write and supervisor
          # teardown. Reuse the same authoritative read the retry preflight
          # uses so the badge matches the persisted lifecycle field.
          state: lifecycle_state(enactment_id)
        }

      {:fallback, reason} ->
        Logger.debug(fn ->
          "EnactmentDetailStore: live peek unavailable for #{inspect(enactment_id)} " <>
            "(#{inspect(reason)}); seeding from storage snapshot + replay"
        end)

        seed_from_storage(enactment_id)
    end
  end

  # Authoritative lifecycle read used by both the mount-time seed and the
  # `:retry_enactment` preflight. Same code path as
  # `authoritative_enactment_state/1`, but degraded to `:running` on
  # `:not_found` / DB errors so a transient outage cannot hide a live
  # enactment from the detail view.
  defp lifecycle_state(enactment_id) do
    case authoritative_enactment_state(enactment_id) do
      {:ok, state} -> state
      {:error, _reason} -> :running
    end
  end

  defp seed_from_storage(enactment_id) do
    if repo_configured?() do
      {markings, version} = read_storage_markings(enactment_id)

      %{
        markings: markings,
        workitems: read_storage_workitems(enactment_id),
        occurrences: seed_occurrences(enactment_id),
        version: version,
        state: lifecycle_state(enactment_id)
      }
    else
      Logger.warning(
        "EnactmentDetailStore seed skipped: no Ecto repo configured under " <>
          ":coloured_flow, ColouredFlow.Runner.Storage."
      )

      %{markings: [], workitems: [], occurrences: [], version: 0, state: :running}
    end
  end

  defp peek_live_enactment(enactment_id) do
    case GenServer.whereis(enactment_via(enactment_id)) do
      nil -> {:fallback, :no_proc}
      pid when is_pid(pid) -> {:ok, :sys.get_state(pid, @peek_timeout_ms)}
    end
  catch
    :exit, {:timeout, _info} -> {:fallback, :timeout}
    :exit, {:noproc, _info} -> {:fallback, :no_proc}
    :exit, reason -> {:fallback, {:exit, reason}}
  end

  # The runner registers enactment GenServers under
  # `ColouredFlow.Runner.Enactment.Registry` with key `{:enactment, id}`. The
  # registry process name is public (it's a named child of the runner's
  # supervision tree); the wrapping `via` tuple is a standard OTP construct.
  # We use it instead of aliasing the runner's internal `Registry` module so
  # the dashboard stays off the `@moduledoc false` surface while still being
  # able to look up running enactments via the public `GenServer.whereis/1`.
  defp enactment_via(enactment_id) when is_binary(enactment_id) do
    {:via, Registry, {ColouredFlow.Runner.Enactment.Registry, {:enactment, enactment_id}}}
  end

  defp read_storage_markings(enactment_id) do
    {initial_markings, snapshot_version} =
      case Storage.read_enactment_snapshot(enactment_id) do
        {:ok, %Snapshot{markings: markings, version: version}} ->
          {markings, version}

        _other ->
          {Storage.get_initial_markings(enactment_id), 0}
      end

    occurrences = Storage.occurrences_stream(enactment_id, snapshot_version)
    {steps, markings} = CatchingUp.apply(initial_markings, occurrences)

    {Enum.map(markings, &marking_row/1), snapshot_version + steps}
  rescue
    _error -> {[], 0}
  end

  defp read_storage_workitems(enactment_id) do
    [limit: @workitem_limit]
    |> WorkitemStream.live_query()
    |> where([w], w.enactment_id == ^enactment_id)
    |> WorkitemStream.list_live()
    |> case do
      :end_of_stream -> []
      {workitems, _cursor} -> Enum.map(workitems, &schema_workitem_row(&1, enactment_id))
    end
  end

  # Storage exposes only `occurrences_stream(enactment_id, from)`, which
  # yields `%ColouredFlow.Enactment.Occurrence{}` structs (no step_number).
  # We pair each occurrence with `from + offset + 1` so the synthetic
  # `OccurrenceRow.id` matches the storage row's `(enactment_id, step_number)`
  # primary key. Reading the stream twice would diverge — instead we read
  # once, drop the head while exceeding `@occurrence_limit * 2`, and tail-slice
  # the most-recent N.
  defp seed_occurrences(enactment_id) do
    if repo_configured?() do
      pairs =
        enactment_id
        |> Storage.occurrences_stream(0)
        |> Stream.with_index(1)
        |> Enum.to_list()

      pairs
      |> Enum.take(-@occurrence_limit)
      |> Enum.reverse()
      |> Enum.map(fn {occ, step_number} -> occurrence_row(occ, enactment_id, step_number) end)
    else
      []
    end
  rescue
    _error -> []
  end

  defp last_occurrence_at([]), do: nil
  defp last_occurrence_at([%OccurrenceRow{occurred_at: at} | _rest]), do: at

  # Persisted snapshot floor, surfaced only as a diagnostic in command
  # replies. `version_range.min` is invariantly 0; this value lets the SPA
  # show "snapshot floor at vK" hints when relevant.
  defp current_snapshot_floor(enactment_id) do
    if repo_configured?() do
      case Storage.read_enactment_snapshot(enactment_id) do
        {:ok, %Snapshot{version: version}} -> version
        _other -> 0
      end
    else
      0
    end
  rescue
    _error -> 0
  end

  defp coerce_version(v) when is_integer(v) and v >= 0, do: {:ok, v}
  defp coerce_version(_other), do: :error

  # `derive_replay/2` reconstructs the marking at `target_version` by
  # replaying the persisted occurrence stream against the nearest ≤
  # base. The live `Runner.Enactment` GenServer is NOT touched — this
  # path uses only `Storage.read_enactment_snapshot/1` +
  # `Storage.get_initial_markings/1` + `Storage.occurrences_stream/2` +
  # `CatchingUp.apply/2`, all of which are read-only public surfaces.
  #
  # For `target_version ≥ snapshot_version` the persisted snapshot is
  # the fast path. For any earlier target — including v0 — the base
  # MUST drop back to the initial markings, otherwise the snapshot
  # floor would hide the initial state from the scrubber.
  defp derive_replay(socket, target_version)
       when is_integer(target_version) and target_version >= 0 do
    enactment_id = socket.assigns.enactment_id
    available_max = socket.assigns.summary.version_range.max

    cond do
      not repo_configured?() ->
        {:error, :runner_error, %{message: "storage repo not configured"}}

      target_version > available_max ->
        {:error, :above_max, %{available_max_version: available_max}}

      true ->
        do_derive_replay(enactment_id, target_version)
    end
  end

  defp do_derive_replay(enactment_id, target_version) do
    # Pick the nearest base ≤ target_version. The persisted snapshot is the
    # fast path for target ≥ snapshot_version; for any earlier target we
    # MUST start from `Storage.get_initial_markings/1` and replay 1..target
    # against `occurrences_stream(eid, 0)`, otherwise the snapshot floor
    # would hide the initial state from the scrubber.
    {initial_markings, base_version} =
      case Storage.read_enactment_snapshot(enactment_id) do
        {:ok, %Snapshot{markings: markings, version: version}}
        when target_version >= version ->
          {markings, version}

        _other ->
          {Storage.get_initial_markings(enactment_id), 0}
      end

    step_count = target_version - base_version

    occurrences =
      enactment_id
      |> Storage.occurrences_stream(base_version)
      |> Stream.take(step_count)

    {_steps, derived} = CatchingUp.apply(initial_markings, occurrences)
    marking_rows = Enum.map(derived, &marking_row/1)
    marking_index = build_marking_index(marking_rows)

    replay_state = %ReplayState{
      version: target_version,
      derived_at: DateTime.to_iso8601(DateTime.utc_now())
    }

    {:ok, marking_rows, replay_state, marking_index}
  rescue
    error -> {:error, :runner_error, %{message: Exception.message(error)}}
  end

  defp replay_error_fields(:above_max, %{available_max_version: max}, socket) do
    %{
      available_max_version: max,
      snapshot_floor: current_snapshot_floor(socket.assigns.enactment_id)
    }
  end

  defp replay_error_fields(:runner_error, info, socket) do
    %{
      code: :runner_error,
      message: Map.get(info, :message, ""),
      available_max_version: socket.assigns.summary.version_range.max,
      snapshot_floor: current_snapshot_floor(socket.assigns.enactment_id)
    }
  end

  defp repo_configured? do
    case Application.get_env(:coloured_flow, ColouredFlow.Runner.Storage) do
      nil -> false
      cfg when is_list(cfg) -> not is_nil(Keyword.get(cfg, :repo))
      _other -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Event routing
  # ---------------------------------------------------------------------------

  defp route_event(%Event{kind: kind} = event, socket)
       when kind in [:produce_workitems_stop, :start_workitems_stop] do
    upsert_workitems(event, socket)
  end

  defp route_event(%Event{kind: :withdraw_workitems_stop} = event, socket) do
    delete_workitems(event, socket)
  end

  defp route_event(%Event{kind: :complete_workitems_stop} = event, socket) do
    socket
    |> delete_workitems_only(event)
    |> insert_occurrences_from(event)
  end

  defp route_event(%Event{kind: :enactment_take_snapshot} = event, socket) do
    bump_summary(socket, version: event.enactment_version)
  end

  defp route_event(%Event{kind: :enactment_terminate} = event, socket) do
    socket
    |> clear_workitems()
    |> bump_summary(
      state: :terminated,
      version: event.enactment_version,
      last_exception_banner: nil
    )
  end

  defp route_event(%Event{kind: :enactment_exception} = event, socket) do
    banner =
      case event.payload do
        %{error_banner: b} when is_binary(b) -> b
        _other -> "Enactment exception"
      end

    bump_summary(socket,
      state: :exception,
      version: event.enactment_version,
      last_exception_banner: banner
    )
  end

  defp route_event(%Event{kind: :enactment_start} = event, socket) do
    bump_summary(socket, state: :running, version: event.enactment_version)
  end

  defp route_event(%Event{}, socket), do: socket

  defp upsert_workitems(%Event{payload: %{workitems: workitems}} = event, socket) do
    enactment_id = event.enactment_id

    Enum.reduce(workitems, socket, fn %RunnerWorkitem{} = wi, acc ->
      apply_workitem(acc, wi, enactment_id, event.enactment_version)
    end)
  end

  defp upsert_workitems(%Event{}, socket), do: socket

  defp apply_workitem(socket, %RunnerWorkitem{state: state} = wi, enactment_id, version)
       when state in @live_states do
    cpnet = cached_cpnet(enactment_id, socket.assigns.flow_cache)
    row = wi |> workitem_row(enactment_id) |> stamp_output_vars(cpnet)
    workitem_ids = MapSet.put(socket.assigns.workitem_ids, row.id)
    meta = WorkitemCompletion.build_meta(enactment_id, row.output_vars)
    workitem_meta = Map.put(socket.assigns.workitem_meta, row.id, meta)

    socket
    |> stream_insert(:workitems, row)
    |> assign(:workitem_ids, workitem_ids)
    |> assign(:workitem_meta, workitem_meta)
    |> bump_summary(version: version, workitems_count: MapSet.size(workitem_ids))
  end

  defp apply_workitem(socket, %RunnerWorkitem{id: id}, _enactment_id, version) do
    workitem_ids = MapSet.delete(socket.assigns.workitem_ids, id)
    workitem_meta = Map.delete(socket.assigns.workitem_meta, id)

    socket
    |> stream_delete_by_item_key(:workitems, id)
    |> assign(:workitem_ids, workitem_ids)
    |> assign(:workitem_meta, workitem_meta)
    |> bump_summary(version: version, workitems_count: MapSet.size(workitem_ids))
  end

  defp delete_workitems(%Event{} = event, socket), do: delete_workitems_only(socket, event)

  defp delete_workitems_only(socket, %Event{payload: %{workitems: workitems}} = event) do
    socket =
      Enum.reduce(workitems, socket, fn %RunnerWorkitem{id: id}, acc ->
        ids = MapSet.delete(acc.assigns.workitem_ids, id)
        meta = Map.delete(acc.assigns.workitem_meta, id)

        acc
        |> stream_delete_by_item_key(:workitems, id)
        |> assign(:workitem_ids, ids)
        |> assign(:workitem_meta, meta)
      end)

    bump_summary(socket,
      version: event.enactment_version,
      workitems_count: MapSet.size(socket.assigns.workitem_ids)
    )
  end

  defp delete_workitems_only(socket, %Event{}), do: socket

  defp clear_workitems(socket) do
    ids = MapSet.to_list(socket.assigns.workitem_ids)

    socket =
      Enum.reduce(ids, socket, fn id, acc ->
        stream_delete_by_item_key(acc, :workitems, id)
      end)

    socket
    |> assign(:workitem_ids, MapSet.new())
    |> assign(:workitem_meta, %{})
    |> bump_summary(workitems_count: 0)
  end

  defp insert_occurrences_from(socket, %Event{
         payload: %{workitems: workitems},
         enactment_id: eid,
         enactment_version: version,
         occurred_at: at
       }) do
    occurred_at = datetime_to_iso(at)
    base_step = version - length(workitems)

    socket =
      workitems
      |> Enum.with_index()
      |> Enum.reduce(socket, fn {%RunnerWorkitem{} = wi, index}, acc ->
        # Bridge payload does not currently carry the storage step_number for
        # each completed workitem. We derive a monotonic synthetic step from
        # the post-event version (one occurrence per workitem in this stop
        # event, in delivery order) so `OccurrenceRow.id` is stable across
        # broadcasts and the stream's `item_key` never collides.
        step_number = base_step + index + 1

        row = %OccurrenceRow{
          id: "#{eid}-#{step_number}",
          step_number: step_number,
          transition: transition_label(wi.binding_element),
          binding_summary: format_binding(wi.binding_element),
          occurred_at: occurred_at,
          outputs_summary: ""
        }

        stream_insert(acc, :occurrences, row)
      end)

    bump_summary(socket, version: version, last_occurrence_at: occurred_at)
  end

  defp insert_occurrences_from(socket, %Event{}), do: socket

  defp bump_summary(socket, fields) when is_list(fields) do
    summary = struct!(socket.assigns.summary, Map.new(fields))
    summary = stretch_version_range(summary, Keyword.get(fields, :version))
    assign(socket, :summary, summary)
  end

  defp put_replay_state(socket, replay_state) do
    summary = %{socket.assigns.summary | replay_state: replay_state}
    assign(socket, :summary, summary)
  end

  defp stretch_version_range(%EnactmentSummary{} = summary, nil), do: summary

  defp stretch_version_range(%EnactmentSummary{version_range: nil} = summary, _version),
    do: summary

  defp stretch_version_range(
         %EnactmentSummary{version_range: %VersionRange{} = range} = summary,
         version
       )
       when is_integer(version) do
    %{summary | version_range: %{range | max: max(range.max, version)}}
  end

  # ---------------------------------------------------------------------------
  # Row builders
  # ---------------------------------------------------------------------------

  defp marking_row(%Marking{place: place, tokens: tokens}) do
    %MarkingRow{
      place: place,
      colour_set: "",
      tokens_count: MultiSet.size(tokens),
      tokens_summary: format_tokens(tokens)
    }
  end

  defp cached_cpnet(enactment_id, flow_cache)
       when is_binary(enactment_id) and is_atom(flow_cache) do
    case lookup_cpnet_safe(enactment_id, flow_cache) do
      {:ok, %ColouredPetriNet{} = cpnet} -> cpnet
      :error -> nil
    end
  end

  defp cached_cpnet(_eid, _cache), do: nil

  @spec stamp_output_vars(WorkitemRow.t(), ColouredPetriNet.t() | nil) :: WorkitemRow.t()
  defp stamp_output_vars(%WorkitemRow{transition: transition} = row, cpnet) do
    %WorkitemRow{row | output_vars: resolve_output_vars(cpnet, transition)}
  end

  defp resolve_output_vars(nil, _transition), do: []

  defp resolve_output_vars(%ColouredPetriNet{} = cpnet, transition),
    do: OutputSchemaBuilder.build(cpnet, transition)

  defp build_workitem_meta(rows, enactment_id) when is_list(rows) and is_binary(enactment_id) do
    Map.new(rows, fn %WorkitemRow{id: id, output_vars: schema} ->
      {id, WorkitemCompletion.build_meta(enactment_id, schema)}
    end)
  end

  defp workitem_row(%RunnerWorkitem{} = wi, enactment_id) do
    %WorkitemRow{
      id: wi.id,
      enactment_id: enactment_id,
      flow_topic_id: nil,
      transition: transition_label(wi.binding_element),
      state: wi.state,
      enactment_state: :running,
      binding_summary: format_binding(wi.binding_element),
      binding_pairs: binding_pairs(wi.binding_element),
      output_vars: [],
      enabled_at: "",
      updated_at: ""
    }
  end

  defp schema_workitem_row(%Schemas.Workitem{} = w, enactment_id) do
    %WorkitemRow{
      id: w.id,
      enactment_id: enactment_id,
      flow_topic_id: nil,
      transition: transition_label(w.binding_element),
      state: w.state,
      enactment_state: :running,
      binding_summary: format_binding(w.binding_element),
      binding_pairs: binding_pairs(w.binding_element),
      output_vars: [],
      enabled_at: datetime_to_iso(w.inserted_at),
      updated_at: datetime_to_iso(w.updated_at)
    }
  end

  defp occurrence_row(%Occurrence{} = occ, enactment_id, step_number) do
    %OccurrenceRow{
      id: "#{enactment_id}-#{step_number}",
      step_number: step_number,
      transition: transition_label(occ.binding_element),
      binding_summary: format_binding(occ.binding_element),
      occurred_at: "",
      outputs_summary: format_free_binding(occ.free_binding)
    }
  end

  defp transition_label(%BindingElement{transition: transition}), do: to_string(transition)

  defp format_binding(%BindingElement{binding: binding}) do
    Enum.map_join(binding, ", ", fn {name, value} -> "#{name} = #{inspect(value)}" end)
  end

  defp binding_pairs(%BindingElement{binding: binding}) do
    Enum.map(binding, fn {name, value} ->
      %BindingPair{name: Atom.to_string(name), value: inspect(value)}
    end)
  end

  defp format_free_binding(free_binding) when is_list(free_binding) do
    Enum.map_join(free_binding, ", ", fn
      {name, value} ->
        "#{name} = #{inspect(value)}"

      binding when is_list(binding) ->
        Enum.map_join(binding, ", ", fn {n, v} -> "#{n} = #{inspect(v)}" end)
    end)
  end

  defp format_free_binding(_other), do: ""

  defp format_tokens(%MultiSet{} = tokens) do
    tokens
    |> MultiSet.to_pairs()
    |> Enum.map_join(", ", fn {coef, value} -> "#{coef}×#{inspect(value)}" end)
  end

  defp datetime_to_iso(nil), do: ""
  defp datetime_to_iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp datetime_to_iso(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
  end

  defp resolve_flow_topic_id(enactment_id, flow_cache)
       when is_binary(enactment_id) and is_atom(flow_cache) do
    case :ets.whereis(flow_cache) do
      :undefined ->
        nil

      _table ->
        case TelemetryBridge.lookup_flow_topic_id(enactment_id, flow_cache) do
          {:ok, flow_id} -> flow_id
          :error -> nil
        end
    end
  end

  # Mirrors `FlowCatalogStore.seeded_name_for/1` / `EnactmentListStore.@seed_by_cpnet`
  # so the detail page can render the operator-facing flow name in its H1.
  # Default (Ecto) backend reads `Schemas.Flow.name` for the joined row;
  # InMemory backend matches the cpnet against the four seeded modules.
  # Returns `nil` when neither path can resolve a name — the page falls
  # back to a generic "Enactment" title.
  @seeded_flow_modules [
    ColouredFlowDashboard.Seeds.ApprovalFlow,
    ColouredFlowDashboard.Seeds.IncidentTriageFlow,
    ColouredFlowDashboard.Seeds.PiAgentFlow,
    ColouredFlowDashboard.Seeds.TrafficLightFlow
  ]

  defp resolve_flow_name(enactment_id, flow_cache)
       when is_binary(enactment_id) and is_atom(flow_cache) do
    case Storage.__storage__() do
      ColouredFlow.Runner.Storage.InMemory ->
        resolve_flow_name_in_memory(enactment_id, flow_cache)

      _default ->
        resolve_flow_name_default(enactment_id)
    end
  rescue
    _error -> nil
  end

  defp resolve_flow_name_default(enactment_id) do
    if repo_configured?() do
      query =
        from(e in Schemas.Enactment,
          join: f in Schemas.Flow,
          on: f.id == e.flow_id,
          where: e.id == ^enactment_id,
          select: f.name
        )

      case ColouredFlowDashboard.Repo.one(query) do
        nil -> nil
        name when is_binary(name) -> name
      end
    end
  rescue
    _error -> nil
  end

  defp resolve_flow_name_in_memory(enactment_id, flow_cache) do
    case :ets.whereis(flow_cache) do
      :undefined ->
        nil

      _table ->
        case TelemetryBridge.lookup_cpnet(enactment_id, flow_cache) do
          {:ok, %ColouredPetriNet{} = cpnet} -> seeded_name_for(cpnet)
          :error -> nil
        end
    end
  end

  defp seeded_name_for(%ColouredPetriNet{} = cpnet) do
    Enum.find_value(@seeded_flow_modules, fn mod ->
      if mod.cpnet() == cpnet, do: mod.__cpn__(:name)
    end)
  end

  # ---------------------------------------------------------------------------
  # :force_terminate
  # ---------------------------------------------------------------------------

  defp force_terminate_reply(enactment_id, reason) when is_binary(enactment_id) do
    message = if reason == "", do: "operator-triggered", else: reason

    case Runner.terminate_enactment(enactment_id, message: message) do
      :ok -> %{code: :ok}
    end
  catch
    :exit, {:noproc, _info} -> %{code: :already_terminated}
    :exit, {:normal, _info} -> %{code: :ok}
    :exit, {{:shutdown, _reason}, _info} -> %{code: :ok}
    kind, reason -> %{code: :runner_error, message: Exception.format(kind, reason)}
  end

  # ---------------------------------------------------------------------------
  # :take_snapshot (deviation: see @moduledoc)
  # ---------------------------------------------------------------------------

  defp resolve_transitions(enactment_id, flow_cache)
       when is_binary(enactment_id) and is_atom(flow_cache) do
    case lookup_cpnet_safe(enactment_id, flow_cache) do
      {:ok, cpnet} ->
        cpnet.transitions
        |> Enum.map(& &1.name)
        |> Enum.sort()

      :error ->
        []
    end
  end

  # Mount-time `resolve_transitions/2` runs once; if the bridge cpnet cache
  # is populated AFTER mount (race), the Debug tab would stay empty until
  # the page is remounted. Re-resolve on every matching cf_event whenever
  # the current list is still empty so the picker materialises as soon as
  # the cache catches up. No-op once `transitions` is non-empty.
  defp maybe_refresh_transitions(socket) do
    case socket.assigns.transitions do
      [] ->
        case resolve_transitions(socket.assigns.enactment_id, socket.assigns.flow_cache) do
          [] -> socket
          [_head | _rest] = transitions -> assign(socket, :transitions, transitions)
        end

      [_head | _rest] ->
        socket
    end
  end

  defp lookup_cpnet_safe(enactment_id, flow_cache) do
    case :ets.whereis(flow_cache) do
      :undefined -> :error
      _table -> TelemetryBridge.lookup_cpnet(enactment_id, flow_cache)
    end
  end

  # ---------------------------------------------------------------------------
  # Telemetry stream
  # ---------------------------------------------------------------------------

  defp append_telemetry(socket, %Event{} = event) do
    entry = telemetry_entry(event, socket.assigns.enactment_id)
    stream_insert(socket, :telemetry, entry, at: 0)
  end

  defp telemetry_entry(%Event{} = event, enactment_id) do
    %TelemetryEntry{
      id: synthesize_entry_id(enactment_id),
      kind: event.kind,
      at: datetime_to_iso(event.occurred_at),
      summary: derive_summary(event),
      severity: derive_severity(event.kind),
      payload_json: encode_payload(event.payload)
    }
  end

  defp synthesize_entry_id(enactment_id) do
    "#{enactment_id}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp derive_severity(:enactment_exception), do: :error
  defp derive_severity(:enactment_terminate), do: :warning

  defp derive_severity(kind) when is_atom(kind) do
    if String.ends_with?(Atom.to_string(kind), "_exception"), do: :error, else: :info
  end

  defp derive_summary(%Event{kind: :produce_workitems_stop, payload: %{workitems: workitems}}),
    do: "Produced #{length(workitems)} workitem(s)"

  defp derive_summary(%Event{kind: :start_workitems_stop, payload: %{workitems: workitems}}),
    do: "Started #{length(workitems)} workitem(s)"

  defp derive_summary(%Event{kind: :withdraw_workitems_stop, payload: %{workitems: workitems}}),
    do: "Withdrew #{length(workitems)} workitem(s)"

  defp derive_summary(%Event{kind: :complete_workitems_stop, payload: %{workitems: workitems}}),
    do: "Completed #{length(workitems)} workitem(s)"

  defp derive_summary(%Event{kind: :produce_workitems_start, payload: payload}) do
    case Map.get(payload, :binding_elements, []) do
      [] -> "Producing workitems"
      list -> "Producing #{length(list)} workitem(s)"
    end
  end

  defp derive_summary(%Event{kind: kind, payload: payload})
       when kind in [:start_workitems_start, :withdraw_workitems_start, :complete_workitems_start] do
    case Map.get(payload, :workitem_ids, []) do
      [] -> Atom.to_string(kind)
      list -> "#{Atom.to_string(kind)} (#{length(list)} id(s))"
    end
  end

  defp derive_summary(%Event{kind: :enactment_start, enactment_version: version}),
    do: "Enactment started at version #{version}"

  defp derive_summary(%Event{kind: :enactment_stop}), do: "Enactment GenServer stopped"

  defp derive_summary(%Event{kind: :enactment_take_snapshot, enactment_version: version}),
    do: "Snapshot taken at version #{version}"

  defp derive_summary(%Event{kind: :enactment_terminate, payload: payload}) do
    msg = Map.get(payload, :termination_message) || Map.get(payload, :termination_type) || "force"
    "Enactment terminated: #{inspect_safe(msg)}"
  end

  defp derive_summary(%Event{kind: :enactment_exception, payload: payload}) do
    Map.get(payload, :error_banner) || "Enactment exception"
  end

  defp derive_summary(%Event{kind: kind, payload: payload}) when is_atom(kind) do
    case Map.get(payload, :error_banner) do
      banner when is_binary(banner) -> banner
      _other -> Atom.to_string(kind)
    end
  end

  defp encode_payload(payload) when is_map(payload) do
    JSON.encode!(sanitize_for_json(payload))
  rescue
    _err -> inspect_safe(payload)
  end

  defp encode_payload(_other), do: "{}"

  # Narrowed structural sanitizer for telemetry payloads. Plain maps, lists,
  # tuples, atoms, numbers, booleans, nil, and binaries are recursively
  # normalised into JSON-friendly shapes. Structs are first probed against
  # the consolidated `JSON.Encoder` protocol (Elixir 1.18+) — those that
  # implement the protocol pass through untouched so `JSON.encode!/1` can
  # serialise them losslessly (e.g. `DateTime`). Only structs WITHOUT a
  # `JSON.Encoder` implementation fall back to `inspect_safe/1`, which is
  # where runner internals like `BindingElement`, `Workitem`, etc. end up.
  defp sanitize_for_json(value) when is_struct(value) do
    case JSON.Encoder.impl_for(value) do
      nil -> inspect_safe(value)
      _impl -> value
    end
  end

  defp sanitize_for_json(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {sanitize_key(k), sanitize_for_json(v)} end)
  end

  defp sanitize_for_json(value) when is_list(value), do: Enum.map(value, &sanitize_for_json/1)
  defp sanitize_for_json(value) when is_binary(value) or is_number(value), do: value
  defp sanitize_for_json(value) when is_boolean(value) or is_nil(value), do: value
  defp sanitize_for_json(value) when is_atom(value), do: Atom.to_string(value)

  defp sanitize_for_json(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&sanitize_for_json/1)

  defp sanitize_for_json(value), do: inspect_safe(value)

  defp sanitize_key(k) when is_binary(k), do: k
  defp sanitize_key(k) when is_atom(k), do: Atom.to_string(k)
  defp sanitize_key(k), do: inspect_safe(k)

  defp inspect_safe(value), do: inspect(value, limit: 50, printable_limit: 200)

  # ---------------------------------------------------------------------------
  # :inspect_transition
  # ---------------------------------------------------------------------------

  defp inspect_transition_reply(socket, transition) when is_binary(transition) do
    enactment_id = socket.assigns.enactment_id
    flow_cache = socket.assigns.flow_cache

    case lookup_cpnet_safe(enactment_id, flow_cache) do
      {:ok, cpnet} ->
        case peek_markings(enactment_id) do
          {:ok, markings} ->
            do_inspect(cpnet, markings, transition)

          :error ->
            %{
              code: :cpnet_unavailable,
              transition: transition,
              info: nil,
              candidates: []
            }
        end

      :error ->
        %{
          code: :cpnet_unavailable,
          transition: transition,
          info: nil,
          candidates: []
        }
    end
  end

  defp do_inspect(cpnet, markings, transition) do
    case BindingInspector.inspect(cpnet, markings, transition) do
      {:ok, info, candidates} ->
        %{
          code: :ok,
          transition: transition,
          info: %TransitionDebugInfo{
            transition: info.transition,
            candidates_count: info.candidates_count,
            enabled_count: info.enabled_count,
            rejected_by_guard_count: info.rejected_by_guard_count,
            rejected_by_arc_eval_count: info.rejected_by_arc_eval_count,
            rejected_by_marking_count: info.rejected_by_marking_count
          },
          candidates:
            Enum.map(candidates, fn c ->
              %BindingCandidate{
                transition: transition,
                binding_summary: c.binding_summary,
                guard_status: c.guard_status,
                reason: c.reason
              }
            end)
        }

      {:error, :unknown_transition} ->
        %{
          code: :unknown_transition,
          transition: transition,
          info: nil,
          candidates: []
        }
    end
  end

  # Returns the current markings map for inspection — same hierarchy as
  # `seed_world/1` (live peek → storage snapshot+replay). Read-only.
  defp peek_markings(enactment_id) do
    case peek_live_enactment(enactment_id) do
      {:ok, %RunnerEnactment{markings: markings}} ->
        {:ok, markings}

      {:fallback, _reason} ->
        storage_markings(enactment_id)
    end
  end

  defp storage_markings(enactment_id) do
    if repo_configured?() do
      {initial_markings, snapshot_version} =
        case Storage.read_enactment_snapshot(enactment_id) do
          {:ok, %Snapshot{markings: markings, version: version}} -> {markings, version}
          _other -> {Storage.get_initial_markings(enactment_id), 0}
        end

      occurrences = Storage.occurrences_stream(enactment_id, snapshot_version)
      {_steps, replayed} = CatchingUp.apply(initial_markings, occurrences)
      {:ok, Map.new(replayed, fn %Marking{place: p} = m -> {p, m} end)}
    else
      :error
    end
  rescue
    _error -> :error
  end

  # ---------------------------------------------------------------------------
  # Net diagram
  # ---------------------------------------------------------------------------

  defp build_marking_index(rows) when is_list(rows) do
    Map.new(rows, fn %MarkingRow{place: p} = row -> {p, row} end)
  end

  # `enabled_workitems :: %{wi_id => transition_name}` records every workitem
  # currently in the runner's `:enabled` state, sourced exclusively from
  # mount-time peek + lifecycle events. The diagram glow then reflects the
  # number of distinct workitems sitting on a transition, matching the
  # "enabled transitions glow" requirement (`:started` workitems are live but
  # no longer enabled and intentionally do NOT contribute to the glow count).
  defp seed_enabled_workitems(rows) when is_list(rows) do
    for %WorkitemRow{state: :enabled, id: id, transition: t} <- rows, into: %{}, do: {id, t}
  end

  defp build_diagram(enactment_id, flow_cache, marking_index, enabled_workitems, fired_at_index) do
    case lookup_cpnet_safe(enactment_id, flow_cache) do
      {:ok, cpnet} ->
        counts = enabled_counts_from(enabled_workitems)

        %NetDiagram{
          places: diagram_places(cpnet, marking_index),
          transitions: diagram_transitions(cpnet, counts, fired_at_index),
          arcs: diagram_arcs(cpnet),
          colour_sets: ColourSetSummary.build(cpnet.colour_sets)
        }

      :error ->
        %NetDiagram{places: [], transitions: [], arcs: [], colour_sets: []}
    end
  end

  defp enabled_counts_from(enabled_workitems) when is_map(enabled_workitems) do
    Enum.frequencies_by(enabled_workitems, fn {_id, transition} -> transition end)
  end

  defp diagram_places(cpnet, marking_index) do
    Enum.map(cpnet.places, fn place ->
      colour_set = colour_set_to_string(place.colour_set)

      case Map.get(marking_index, place.name) do
        %MarkingRow{tokens_count: count, tokens_summary: summary} ->
          %NetDiagramPlace{
            name: place.name,
            colour_set: colour_set,
            tokens_count: count,
            tokens_summary: summary
          }

        nil ->
          %NetDiagramPlace{
            name: place.name,
            colour_set: colour_set,
            tokens_count: 0,
            tokens_summary: ""
          }
      end
    end)
  end

  defp diagram_transitions(cpnet, counts, fired_at_index) do
    Enum.map(cpnet.transitions, fn transition ->
      %NetDiagramTransition{
        name: transition.name,
        enabled_count: Map.get(counts, transition.name, 0),
        rejected_by_guard_count: 0,
        rejected_by_arc_eval_count: 0,
        rejected_by_marking_count: 0,
        last_fired_at: Map.get(fired_at_index, transition.name)
      }
    end)
  end

  defp diagram_arcs(cpnet) do
    Enum.map(cpnet.arcs, fn arc ->
      %NetDiagramArc{
        place: arc.place,
        transition: arc.transition,
        orientation: arc.orientation
      }
    end)
  end

  defp colour_set_to_string(nil), do: ""
  defp colour_set_to_string(name) when is_atom(name), do: Atom.to_string(name)
  defp colour_set_to_string(name) when is_binary(name), do: name
  defp colour_set_to_string(other), do: inspect(other)

  # Enabled-set maintenance. `enabled_workitems` is the precise membership
  # set of workitems currently in the runner's `:enabled` state, keyed by
  # workitem id. Lifecycle transitions:
  #
  #   * `:produce_workitems_stop`   — workitem enters `:enabled`        → add
  #   * `:start_workitems_stop`     — workitem leaves `:enabled`        → drop
  #   * `:withdraw_workitems_stop`  — workitem killed (from either)     → drop
  #   * `:complete_workitems_stop`  — workitem fired (was `:started`)   → drop
  #     (already absent after the matching start; the drop is a safety net
  #     for missed start events.)
  #   * `:enactment_terminate`      — every workitem gone               → clear
  #
  # The diagram glow on a transition is `count of entries with that
  # transition_name`. `:started` workitems contribute zero, matching the
  # immutable requirement ("enabled transitions glow").
  defp apply_diagram_event(socket, %Event{kind: :complete_workitems_stop} = event) do
    socket
    |> record_transition_firings(event)
    |> drop_enabled_workitems(event)
  end

  defp apply_diagram_event(socket, %Event{kind: :produce_workitems_stop} = event) do
    add_enabled_workitems(socket, event)
  end

  defp apply_diagram_event(socket, %Event{kind: kind} = event)
       when kind in [:start_workitems_stop, :withdraw_workitems_stop] do
    drop_enabled_workitems(socket, event)
  end

  defp apply_diagram_event(socket, %Event{kind: :enactment_terminate}) do
    assign(socket, :enabled_workitems, %{})
  end

  defp apply_diagram_event(socket, %Event{}), do: socket

  defp record_transition_firings(socket, %Event{payload: %{workitems: workitems}, occurred_at: at}) do
    fired_at_iso = datetime_to_iso(at)

    fired_at_index =
      Enum.reduce(workitems, socket.assigns.transition_fired_at, fn wi, acc ->
        Map.put(acc, transition_label(wi.binding_element), fired_at_iso)
      end)

    assign(socket, :transition_fired_at, fired_at_index)
  end

  defp record_transition_firings(socket, %Event{}), do: socket

  defp add_enabled_workitems(socket, %Event{payload: %{workitems: workitems}}) do
    next =
      Enum.reduce(workitems, socket.assigns.enabled_workitems, fn wi, acc ->
        Map.put(acc, wi.id, transition_label(wi.binding_element))
      end)

    assign(socket, :enabled_workitems, next)
  end

  defp add_enabled_workitems(socket, %Event{}), do: socket

  defp drop_enabled_workitems(socket, %Event{payload: %{workitems: workitems}}) do
    next =
      Enum.reduce(workitems, socket.assigns.enabled_workitems, fn wi, acc ->
        Map.delete(acc, wi.id)
      end)

    assign(socket, :enabled_workitems, next)
  end

  defp drop_enabled_workitems(socket, %Event{}), do: socket

  # `:complete_workitems_stop` is the only event that consumes/produces tokens.
  # `:enactment_terminate` doesn't move tokens but the marking view should
  # reflect the final post-terminate state if the runner persisted any cleanup
  # marking — schedule one last refresh.
  defp maybe_schedule_marking_refresh(socket, %Event{kind: kind})
       when kind in [:complete_workitems_stop, :enactment_terminate] do
    schedule_marking_refresh(socket)
  end

  defp maybe_schedule_marking_refresh(socket, %Event{}), do: socket

  defp schedule_marking_refresh(socket) do
    if socket.assigns.marking_refresh_pending do
      socket
    else
      Process.send_after(self(), :refresh_markings, @marking_refresh_delay_ms)
      assign(socket, :marking_refresh_pending, true)
    end
  end

  defp refresh_markings_now(socket) do
    case peek_markings_world(socket.assigns.enactment_id) do
      {:ok, rows, version} ->
        marking_index = build_marking_index(rows)

        socket
        |> stream(:markings, rows, reset: true)
        |> assign(:marking_index, marking_index)
        |> bump_summary(version: version, markings_count: length(rows))

      :error ->
        socket
    end
  end

  # Authoritative current markings + version (live runner peek → storage
  # snapshot+replay fallback). Same hierarchy as `seed_world/1`; never
  # re-derives markings from event payloads (would duplicate runner
  # multiset arithmetic on the dashboard side).
  defp peek_markings_world(enactment_id) do
    case peek_live_enactment(enactment_id) do
      {:ok, %RunnerEnactment{markings: markings, version: version}} ->
        rows = markings |> Map.values() |> Enum.map(&marking_row/1)
        {:ok, rows, version}

      {:fallback, reason} ->
        Logger.debug(fn ->
          "EnactmentDetailStore: live marking peek unavailable for " <>
            "#{inspect(enactment_id)} (#{inspect(reason)}); falling back to storage"
        end)

        if repo_configured?() do
          {rows, version} = read_storage_markings(enactment_id)
          {:ok, rows, version}
        else
          :error
        end
    end
  end

  defp refresh_diagram(socket) do
    # When replay is active, the diagram reflects the derived marking
    # snapshot (M7a) so the place token badges match the Markings tab.
    # Workitem-driven glow + last_fired_at stay on the live signal — only
    # the place counts swap.
    # Musubi.Socket.assign/3 skips the assign when the value is unchanged,
    # so an initial nil never lands in the map. Read via Map.get so first
    # access doesn't blow up before the operator enters replay mode.
    marking_index =
      Map.get(socket.assigns, :replay_marking_index) || socket.assigns.marking_index

    diagram =
      build_diagram(
        socket.assigns.enactment_id,
        socket.assigns.flow_cache,
        marking_index,
        socket.assigns.enabled_workitems,
        socket.assigns.transition_fired_at
      )

    assign(socket, :diagram, diagram)
  end

  defp take_snapshot_reply(enactment_id) do
    case GenServer.whereis(enactment_via(enactment_id)) do
      nil ->
        %{code: :not_running}

      pid when is_pid(pid) ->
        send(pid, :take_snapshot)
        %{code: :ok}
    end
  catch
    kind, reason -> %{code: :runner_error, message: Exception.format(kind, reason)}
  end

  # `:retry_enactment` (M6) — re-reads the authoritative enactment state
  # from storage BEFORE dispatching. The Musubi-cached `summary.state` can
  # lag behind a concurrent force-terminate; trusting it would let an
  # already-`:terminated` row be resurrected back to `:running` by
  # `Storage.retry_enactment/2`. Only an actual `:exception` row is retried.
  defp retry_enactment_reply(enactment_id) when is_binary(enactment_id) do
    case authoritative_enactment_state(enactment_id) do
      {:ok, :exception} -> do_retry_enactment(enactment_id)
      {:ok, :running} -> %{code: :not_exception}
      {:ok, :terminated} -> %{code: :already_terminated}
      {:error, reason} -> %{code: :runner_error, message: inspect(reason)}
    end
  end

  defp do_retry_enactment(enactment_id) do
    :ok = Storage.retry_enactment(enactment_id, message: "operator-triggered")

    case Runner.start_enactment(enactment_id) do
      {:ok, _pid} -> %{code: :ok}
      {:error, reason} -> %{code: :runner_error, message: inspect(reason)}
    end
  rescue
    error -> %{code: :runner_error, message: Exception.message(error)}
  catch
    kind, reason -> %{code: :runner_error, message: Exception.format(kind, reason)}
  end

  # No public `Storage` callback exposes just the state; the dashboard's
  # `read_storage_state/1` swallows errors into `:running`, which would
  # silently allow retries on transient DB outages. Read once here with
  # explicit `:error` semantics so the gate above can fail closed.
  defp authoritative_enactment_state(enactment_id) do
    case ColouredFlowDashboard.Repo.get(Schemas.Enactment, enactment_id) do
      %Schemas.Enactment{state: state} -> {:ok, state}
      nil -> {:error, :not_found}
    end
  rescue
    error -> {:error, error}
  end
end
