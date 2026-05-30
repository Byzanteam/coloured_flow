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

  The bridge payload does not carry post-event markings, so on
  `:complete_workitems_stop` we cannot deterministically rebuild the
  `:markings` stream from the event alone. M3a treats markings as
  mount-time-accurate; a later phase will upgrade the bridge payload with
  per-event marking deltas. Until then, the SPA shows an inline `Banner`
  on the Markings tab telling the operator to take a snapshot and reload
  the page to refresh.

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

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.MultiSet
  alias ColouredFlow.Runner.Enactment, as: RunnerEnactment
  alias ColouredFlow.Runner.Enactment.CatchingUp
  alias ColouredFlow.Runner.Enactment.Registry, as: EnactmentRegistry
  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Enactment.Supervisor, as: EnactmentSupervisor
  alias ColouredFlow.Runner.Enactment.Workitem, as: RunnerWorkitem
  alias ColouredFlow.Runner.Storage
  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlow.Runner.Worklist.WorkitemStream
  alias ColouredFlowDashboard.BindingInspector
  alias ColouredFlowDashboard.TelemetryBridge
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboardWeb.Views.BindingCandidate
  alias ColouredFlowDashboardWeb.Views.EnactmentSummary
  alias ColouredFlowDashboardWeb.Views.MarkingRow
  alias ColouredFlowDashboardWeb.Views.NetDiagram
  alias ColouredFlowDashboardWeb.Views.NetDiagramArc
  alias ColouredFlowDashboardWeb.Views.NetDiagramPlace
  alias ColouredFlowDashboardWeb.Views.NetDiagramTransition
  alias ColouredFlowDashboardWeb.Views.OccurrenceRow
  alias ColouredFlowDashboardWeb.Views.TelemetryEntry
  alias ColouredFlowDashboardWeb.Views.TransitionDebugInfo
  alias ColouredFlowDashboardWeb.Views.WorkitemRow

  import Ecto.Query, only: [where: 3]

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
    transitions = resolve_transitions(enactment_id, flow_cache)
    last_occurrence_at = last_occurrence_at(occurrences)
    marking_index = build_marking_index(markings)
    enabled_workitems = seed_enabled_workitems(workitems)
    diagram = build_diagram(enactment_id, flow_cache, marking_index, enabled_workitems, %{})

    summary = %EnactmentSummary{
      enactment_id: enactment_id,
      flow_topic_id: flow_topic_id,
      state: state_kind,
      version: version,
      markings_count: length(markings),
      workitems_count: length(workitems),
      last_occurrence_at: last_occurrence_at,
      last_exception_banner: nil
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
      |> assign(:enabled_workitems, enabled_workitems)
      |> assign(:transition_fired_at, %{})
      |> assign(:workitem_ids, MapSet.new(Enum.map(workitems, & &1.id)))
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
    if event.enactment_id == socket.assigns.enactment_id do
      socket =
        event
        |> route_event(socket)
        |> append_telemetry(event)
        |> maybe_refresh_transitions()
        |> apply_diagram_event(event)
        |> refresh_diagram()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

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
    {:reply, retry_enactment_reply(socket.assigns.enactment_id, socket.assigns.summary.state),
     socket}
  end

  def handle_command(:inspect_transition, payload, socket) when is_map(payload) do
    transition = Map.get(payload, "transition") || Map.get(payload, :transition) || ""
    {:reply, inspect_transition_reply(socket, transition), socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}

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
          state: :running
        }

      {:fallback, reason} ->
        Logger.debug(fn ->
          "EnactmentDetailStore: live peek unavailable for #{inspect(enactment_id)} " <>
            "(#{inspect(reason)}); seeding from storage snapshot + replay"
        end)

        seed_from_storage(enactment_id)
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
        state: read_storage_state(enactment_id)
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
    via = EnactmentRegistry.via_name({:enactment, enactment_id})

    case GenServer.whereis(via) do
      nil -> {:fallback, :no_proc}
      pid when is_pid(pid) -> {:ok, :sys.get_state(pid, @peek_timeout_ms)}
    end
  catch
    :exit, {:timeout, _info} -> {:fallback, :timeout}
    :exit, {:noproc, _info} -> {:fallback, :no_proc}
    :exit, reason -> {:fallback, {:exit, reason}}
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

  defp read_storage_state(enactment_id) do
    case ColouredFlowDashboard.Repo.get(Schemas.Enactment, enactment_id) do
      %Schemas.Enactment{state: state} -> state
      nil -> :running
    end
  rescue
    _error -> :running
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
    row = workitem_row(wi, enactment_id)
    workitem_ids = MapSet.put(socket.assigns.workitem_ids, row.id)

    socket
    |> stream_insert(:workitems, row)
    |> assign(:workitem_ids, workitem_ids)
    |> bump_summary(version: version, workitems_count: MapSet.size(workitem_ids))
  end

  defp apply_workitem(socket, %RunnerWorkitem{id: id}, _enactment_id, version) do
    workitem_ids = MapSet.delete(socket.assigns.workitem_ids, id)

    socket
    |> stream_delete_by_item_key(:workitems, id)
    |> assign(:workitem_ids, workitem_ids)
    |> bump_summary(version: version, workitems_count: MapSet.size(workitem_ids))
  end

  defp delete_workitems(%Event{} = event, socket), do: delete_workitems_only(socket, event)

  defp delete_workitems_only(socket, %Event{payload: %{workitems: workitems}} = event) do
    socket =
      Enum.reduce(workitems, socket, fn %RunnerWorkitem{id: id}, acc ->
        ids = MapSet.delete(acc.assigns.workitem_ids, id)

        acc
        |> stream_delete_by_item_key(:workitems, id)
        |> assign(:workitem_ids, ids)
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
    assign(socket, :summary, summary)
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

  defp workitem_row(%RunnerWorkitem{} = wi, enactment_id) do
    %WorkitemRow{
      id: wi.id,
      enactment_id: enactment_id,
      flow_topic_id: nil,
      transition: transition_label(wi.binding_element),
      state: wi.state,
      enactment_state: :running,
      binding_summary: format_binding(wi.binding_element),
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

  # ---------------------------------------------------------------------------
  # :force_terminate
  # ---------------------------------------------------------------------------

  defp force_terminate_reply(enactment_id, reason) when is_binary(enactment_id) do
    message = if reason == "", do: "operator-triggered", else: reason

    case EnactmentSupervisor.terminate_enactment(enactment_id, message: message) do
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
          arcs: diagram_arcs(cpnet)
        }

      :error ->
        %NetDiagram{places: [], transitions: [], arcs: []}
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

  defp refresh_diagram(socket) do
    diagram =
      build_diagram(
        socket.assigns.enactment_id,
        socket.assigns.flow_cache,
        socket.assigns.marking_index,
        socket.assigns.enabled_workitems,
        socket.assigns.transition_fired_at
      )

    assign(socket, :diagram, diagram)
  end

  defp take_snapshot_reply(enactment_id) do
    via = EnactmentRegistry.via_name({:enactment, enactment_id})

    case GenServer.whereis(via) do
      nil ->
        %{code: :not_running}

      pid when is_pid(pid) ->
        send(pid, :take_snapshot)
        %{code: :ok}
    end
  catch
    kind, reason -> %{code: :runner_error, message: Exception.format(kind, reason)}
  end

  # `:retry_enactment` (M6) — runs only when the dashboard's last-seen state
  # is `:exception`. Calls `Storage.retry_enactment/2` (flips DB row →
  # `:running`, writes a `:retried` log) and then asks the runner supervisor
  # to (re)start the enactment GenServer. `start_enactment/2` collapses
  # `{:already_started, pid}` → `{:ok, pid}` so an existing process is not a
  # failure mode.
  defp retry_enactment_reply(_enactment_id, :terminated), do: %{code: :already_terminated}
  defp retry_enactment_reply(_enactment_id, :running), do: %{code: :not_exception}

  defp retry_enactment_reply(enactment_id, :exception) when is_binary(enactment_id) do
    :ok = Storage.retry_enactment(enactment_id, message: "operator-triggered")

    case EnactmentSupervisor.start_enactment(enactment_id) do
      {:ok, _pid} -> %{code: :ok}
      {:error, reason} -> %{code: :runner_error, message: inspect(reason)}
    end
  rescue
    error -> %{code: :runner_error, message: Exception.message(error)}
  catch
    kind, reason -> %{code: :runner_error, message: Exception.format(kind, reason)}
  end
end
