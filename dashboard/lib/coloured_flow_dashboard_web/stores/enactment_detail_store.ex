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
    * `:markings` stream — `MarkingRow` per place, keyed by `place` name.
    * `:workitems` stream — `WorkitemRow` per live workitem (same Wire shape
      used by `InboxStore`), keyed by workitem id.
    * `:occurrences` stream — `OccurrenceRow` per fired occurrence, keyed by
      the synthetic `"<enactment_id>-<step_number>"` id. Capped to 200 rows.

  ## Event routing

  Subscribes to `"cf:enactment:<id>"`. Routing by `Event.kind`:

  | kind                          | action                                                                                          |
  | ----------------------------- | ----------------------------------------------------------------------------------------------- |
  | `:produce_workitems_stop`     | upsert into `:workitems`; bump summary.workitems_count + version                                |
  | `:start_workitems_stop`       | upsert into `:workitems` (`:enabled → :started`)                                                |
  | `:withdraw_workitems_stop`    | delete from `:workitems`                                                                        |
  | `:complete_workitems_stop`    | delete from `:workitems`; insert into `:occurrences` (one per workitem); set last_occurrence_at |
  | `:enactment_take_snapshot`    | bump summary.version                                                                            |
  | `:enactment_terminate`        | summary.state = `:terminated`; flush remaining workitem rows                                    |
  | `:enactment_exception`        | summary.state = `:exception`                                                                    |
  | `:enactment_start`            | summary.state = `:running`; refresh summary.version                                             |
  | everything else               | no-op (`*_workitems_start`, `:enactment_stop`, exception halves)                                |

  Cross-enactment events are filtered out via `event.enactment_id` so the
  store ignores any topic-level crosstalk.

  ## Marking refresh

  The bridge payload does not carry post-event markings, so on
  `:complete_workitems_stop` we cannot deterministically rebuild the
  `:markings` stream from the event alone. M3a treats markings as
  mount-time-accurate; a later phase will upgrade the bridge payload with
  per-event marking deltas. Until then, operators can take a snapshot via the
  action bar and re-mount to refresh markings.

  ## Storage / runner peek strategy

  `seed_world/1` prefers the live GenServer state via `:sys.get_state/1`,
  falling back to `Storage.read_enactment_snapshot/1` +
  `CatchingUp.apply/2` when the GenServer is not running.

  ## Commands

    * `:withdraw_workitem` — DEVIATION: no public runner API withdraws a
      specific workitem (withdrawals happen automatically via
      `WorkitemCalibration`). Storage-level `Storage.withdraw_workitems/2`
      writes the row but leaves the runner GenServer state untouched,
      drifting state. The command always replies `%{code: :unsupported}`
      until main exposes a public withdraw surface.
    * `:force_terminate` — `Runner.Enactment.Supervisor.terminate_enactment/2`
      with the operator-supplied `:message`. Reply codes:
      `:ok | :already_terminated | :runner_error`.
    * `:take_snapshot` — sends a `:take_snapshot` message to the enactment
      GenServer (same hot path the runner uses internally after completions).
      Missing process → `:not_running`.
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
  alias ColouredFlowDashboard.TelemetryBridge
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboardWeb.Views.EnactmentSummary
  alias ColouredFlowDashboardWeb.Views.MarkingRow
  alias ColouredFlowDashboardWeb.Views.OccurrenceRow
  alias ColouredFlowDashboardWeb.Views.WorkitemRow

  import Ecto.Query, only: [where: 3]

  require Logger

  @default_pubsub :coloured_flow_dashboard_pubsub
  @default_topic_prefix "cf:"
  @default_flow_cache :coloured_flow_dashboard_telemetry_bridge_flow_cache
  @occurrence_limit 200
  @workitem_limit 200
  @live_states RunnerWorkitem.__live_states__()

  # Musubi's `state do` type walker resolves `Mod.t()` against the host
  # module's namespace ancestry, not its `alias` table. Inline FQN refs.
  state do
    field :summary, ColouredFlowDashboardWeb.Views.EnactmentSummary.t()

    stream :markings, ColouredFlowDashboardWeb.Views.MarkingRow.t(),
      limit: @workitem_limit,
      item_key: & &1.place

    stream :workitems, ColouredFlowDashboardWeb.Views.WorkitemRow.t(),
      limit: @workitem_limit,
      item_key: & &1.id

    stream :occurrences, ColouredFlowDashboardWeb.Views.OccurrenceRow.t(),
      limit: @occurrence_limit,
      item_key: & &1.id
  end

  command :withdraw_workitem do
    payload do
      field :workitem_id, String.t()
    end

    reply do
      field :code,
            :ok
            | :already_withdrawn
            | :unknown_workitem
            | :unsupported
            | :runner_error
    end
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
    last_occurrence_at = last_occurrence_at(occurrences)

    summary = %EnactmentSummary{
      enactment_id: enactment_id,
      flow_topic_id: flow_topic_id,
      state: state_kind,
      version: version,
      markings_count: length(markings),
      workitems_count: length(workitems),
      last_occurrence_at: last_occurrence_at
    }

    socket =
      socket
      |> assign(:enactment_id, enactment_id)
      |> assign(:pubsub_name, pubsub)
      |> assign(:topic, topic)
      |> assign(:flow_cache, flow_cache)
      |> assign(:summary, summary)
      |> assign(:workitem_ids, MapSet.new(Enum.map(workitems, & &1.id)))
      |> stream(:markings, markings, reset: true)
      |> stream(:workitems, workitems, reset: true)
      |> stream(:occurrences, occurrences, reset: true)

    {:ok, socket}
  end

  @impl Musubi.Store
  def render(socket) do
    %{
      summary: socket.assigns.summary,
      markings: stream(:markings),
      workitems: stream(:workitems),
      occurrences: stream(:occurrences)
    }
  end

  # ---------------------------------------------------------------------------
  # Mailbox
  # ---------------------------------------------------------------------------

  @impl Musubi.Store
  def handle_info({:cf_event, %Event{} = event}, socket) do
    if event.enactment_id == socket.assigns.enactment_id do
      {:noreply, route_event(event, socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Commands
  # ---------------------------------------------------------------------------

  @impl Musubi.Store
  def handle_command(:withdraw_workitem, payload, socket) when is_map(payload) do
    workitem_id = Map.get(payload, "workitem_id") || Map.get(payload, :workitem_id)
    {:reply, withdraw_workitem_reply(workitem_id, socket), socket}
  end

  def handle_command(:force_terminate, payload, socket) when is_map(payload) do
    reason = Map.get(payload, "reason") || Map.get(payload, :reason) || ""
    {:reply, force_terminate_reply(socket.assigns.enactment_id, reason), socket}
  end

  def handle_command(:take_snapshot, _payload, socket) do
    {:reply, take_snapshot_reply(socket.assigns.enactment_id), socket}
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

      :not_running ->
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
      nil -> :not_running
      pid when is_pid(pid) -> {:ok, :sys.get_state(pid)}
    end
  catch
    :exit, _reason -> :not_running
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
    |> bump_summary(state: :terminated, version: event.enactment_version)
  end

  defp route_event(%Event{kind: :enactment_exception} = event, socket) do
    bump_summary(socket, state: :exception, version: event.enactment_version)
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
  # :withdraw_workitem (deviation: see @moduledoc)
  # ---------------------------------------------------------------------------

  defp withdraw_workitem_reply(nil, _socket),
    do: %{code: :unknown_workitem}

  defp withdraw_workitem_reply(workitem_id, socket) when is_binary(workitem_id) do
    if MapSet.member?(socket.assigns.workitem_ids, workitem_id) do
      %{
        code: :unsupported,
        workitem_id: workitem_id,
        message:
          "Withdraw of a specific workitem is not exposed by the public runner " <>
            "API in M3a; the SPA renders this code as a non-actionable toast."
      }
    else
      %{code: :unknown_workitem, workitem_id: workitem_id}
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
end
