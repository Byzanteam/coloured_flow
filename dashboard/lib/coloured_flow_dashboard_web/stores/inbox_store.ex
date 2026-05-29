defmodule ColouredFlowDashboardWeb.Stores.InboxStore do
  @moduledoc """
  Root Musubi store backing the operator inbox at `/`.

  Subscribes to `cf:inbox` (or a per-mount override — see `mount/2`) on the
  dashboard's `Phoenix.PubSub` server and translates the
  `{:cf_event, %ColouredFlowDashboard.TelemetryBridge.Event{}}` payloads
  produced by `ColouredFlowDashboard.TelemetryBridge` into:

    * a `:workitems` stream of `ColouredFlowDashboardWeb.Views.WorkitemRow`s
      (one entry per live workitem, keyed by workitem id), and
    * a top-level `:counts` field of
      `ColouredFlowDashboardWeb.Views.InboxCounts` driving the header badges.

  The initial set is seeded from
  `ColouredFlow.Runner.Worklist.WorkitemStream.live_query/1` +
  `list_live/1` — the same cursor-paged surface the requirements pin. The
  page is truncated to `#{inspect(100)}` rows for M2a; cursor pagination of
  the tail is a later phase.

  ## Mount params

  All optional; defaults match the production wiring.

    * `"pubsub_name"` — name of the `Phoenix.PubSub` server. Defaults to
      `:coloured_flow_dashboard_pubsub`.
    * `"topic"` — topic to subscribe to. Defaults to `"cf:inbox"`. Tests
      pass a per-test topic prefix so parallel suites do not cross-pollute.
    * `"flow_cache"` — ETS table holding the enactment → flow_topic_id
      cache populated by `ColouredFlowDashboard.TelemetryBridge`. Defaults
      to the bridge's `@default_flow_cache`. `flow_topic_id` falls back to
      `nil` on cache miss.

  ## Event routing

  `Event.kinds/0` is the authoritative drift list. Each kind maps to:

  | kind                                                       | action                                              |
  | ---------------------------------------------------------- | --------------------------------------------------- |
  | `:produce_workitems_stop`                                  | upsert row from each `payload.workitems` entry      |
  | `:start_workitems_stop`                                    | upsert (state moves :enabled → :started, still live) |
  | `:withdraw_workitems_stop`                                 | delete from stream (state non-live)                 |
  | `:complete_workitems_stop`                                 | delete from stream (state non-live)                 |
  | `:enactment_terminate`                                     | delete every remaining row for the enactment        |
  | everything else (lifecycle starts, exception, take_snapshot, op `:start`/`:exception` halves) | no-op (counts unchanged) |

  Per-event payloads are treated as eventually consistent: a `cf:flow:<id>`
  side-effect may have been skipped by the bridge on storage-lookup
  failure, so `flow_topic_id` is best-effort and may be `nil` even after
  the corresponding `cf:inbox` event has been observed.
  """

  use Musubi.Store, root: true

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Runner.Enactment.Workitem, as: RunnerWorkitem
  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlow.Runner.Worklist.WorkitemStream
  alias ColouredFlowDashboard.TelemetryBridge
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboardWeb.Views.InboxCounts
  alias ColouredFlowDashboardWeb.Views.WorkitemRow

  require Logger

  @default_pubsub :coloured_flow_dashboard_pubsub
  @default_topic "cf:inbox"
  # Hardcoded in `ColouredFlowDashboard.TelemetryBridge` as the bridge's
  # default flow_cache table. Keeping the two in sync is enforced by the
  # InboxStore tests, not by a cross-module attribute (the bridge owns the
  # cache, the store is a read-side consumer).
  @default_flow_cache :coloured_flow_dashboard_telemetry_bridge_flow_cache
  @stream_limit 100
  @live_states RunnerWorkitem.__live_states__()

  # Musubi's compile-time type walker resolves `Mod.t()` aliases by walking
  # the host module's namespace ancestry, not its `alias` table. Inline the
  # fully-qualified module names so the walker finds them without depending
  # on `Stores.*` ↔ `Views.*` sharing a parent prefix.
  #
  # `item_key: &(&1.id)` makes the stream's insert/delete key shape match
  # the bare workitem UUID passed to `stream_delete_by_item_key/3` — without
  # it the Musubi default (`"workitems-#{id}"`) would never match the
  # delete-site key and completed/withdrawn rows would linger on the client.
  state do
    stream :workitems, ColouredFlowDashboardWeb.Views.WorkitemRow.t(),
      limit: @stream_limit,
      item_key: & &1.id

    field :counts, ColouredFlowDashboardWeb.Views.InboxCounts.t()
  end

  @impl Musubi.Store
  def mount(params, socket) when is_map(params) do
    pubsub = Map.get(params, "pubsub_name", @default_pubsub)
    topic = Map.get(params, "topic", @default_topic)
    flow_cache = Map.get(params, "flow_cache", @default_flow_cache)

    :ok = Phoenix.PubSub.subscribe(pubsub, topic)

    rows = seed_rows(flow_cache)
    enactment_index = build_enactment_index(rows)
    counts = compute_counts(rows, enactment_index)

    socket =
      socket
      |> assign(:pubsub_name, pubsub)
      |> assign(:topic, topic)
      |> assign(:flow_cache, flow_cache)
      |> assign(:enactment_workitems, enactment_index)
      |> assign(:workitem_states, build_state_index(rows))
      |> assign(:counts, counts)
      |> stream(:workitems, rows, reset: true)

    {:ok, socket}
  end

  @impl Musubi.Store
  def render(socket) do
    %{
      workitems: stream(:workitems),
      counts: socket.assigns.counts
    }
  end

  # M2a declares no commands; M2b (outputs drawer) introduces
  # `:complete_workitem`. Stub the required behaviour callback so unknown
  # commands return `{:noreply, socket}` cleanly without crashing the page.
  @impl Musubi.Store
  def handle_command(_name, _payload, socket), do: {:noreply, socket}

  @impl Musubi.Store
  def handle_info({:cf_event, %Event{} = event}, socket) do
    {:noreply, route_event(event, socket)}
  end

  # Drop unrelated mailbox traffic — Phoenix.PubSub-adjacent stores can also
  # receive `:DOWN` and adapter probe messages.
  def handle_info(_other, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Mount-time seed
  # ---------------------------------------------------------------------------

  defp seed_rows(flow_cache) do
    # Check Repo presence *before* dispatching the query so genuine query
    # failures (schema drift, storage outage, etc.) propagate instead of
    # silently degrading the inbox to empty. The only swallowed case is the
    # explicitly-unconfigured environment (e.g. a host app that mounts the
    # dashboard without wiring `:coloured_flow, ColouredFlow.Runner.Storage`).
    if repo_configured?() do
      [limit: @stream_limit]
      |> WorkitemStream.live_query()
      |> WorkitemStream.list_live()
      |> case do
        :end_of_stream -> []
        {workitems, _cursor} -> Enum.map(workitems, &schema_to_row(&1, flow_cache))
      end
    else
      Logger.warning(
        "InboxStore seed skipped: no Ecto repo configured under " <>
          ":coloured_flow, ColouredFlow.Runner.Storage — PubSub will populate the inbox."
      )

      []
    end
  end

  defp repo_configured? do
    case Application.get_env(:coloured_flow, ColouredFlow.Runner.Storage) do
      nil -> false
      cfg when is_list(cfg) -> not is_nil(Keyword.get(cfg, :repo))
      _other -> false
    end
  end

  defp build_enactment_index(rows) do
    Enum.reduce(rows, %{}, fn %WorkitemRow{id: id, enactment_id: eid}, acc ->
      Map.update(acc, eid, MapSet.new([id]), &MapSet.put(&1, id))
    end)
  end

  defp build_state_index(rows) do
    Map.new(rows, fn %WorkitemRow{id: id, state: state} -> {id, state} end)
  end

  defp compute_counts(rows, enactment_index) do
    by_state = Enum.frequencies_by(rows, & &1.state)

    %InboxCounts{
      enabled: Map.get(by_state, :enabled, 0),
      started: Map.get(by_state, :started, 0),
      by_enactment: Map.new(enactment_index, fn {eid, ids} -> {eid, MapSet.size(ids)} end)
    }
  end

  # ---------------------------------------------------------------------------
  # Event routing
  # ---------------------------------------------------------------------------

  defp route_event(
         %Event{kind: kind, enactment_id: eid, occurred_at: at, payload: %{workitems: workitems}},
         socket
       )
       when kind in [
              :produce_workitems_stop,
              :start_workitems_stop,
              :withdraw_workitems_stop,
              :complete_workitems_stop
            ] do
    flow_cache = socket.assigns.flow_cache
    flow_topic_id = resolve_flow_topic_id(eid, flow_cache)

    Enum.reduce(workitems, socket, fn %RunnerWorkitem{} = wi, acc ->
      apply_workitem(acc, wi, eid, flow_topic_id, at)
    end)
  end

  defp route_event(%Event{kind: :enactment_terminate, enactment_id: eid}, socket) do
    ids = Map.get(socket.assigns.enactment_workitems, eid, MapSet.new())

    Enum.reduce(ids, socket, &drop_workitem(&2, &1))
  end

  defp route_event(%Event{}, socket), do: socket

  defp apply_workitem(socket, %RunnerWorkitem{state: state} = wi, eid, flow_topic_id, at)
       when state in @live_states do
    row = runtime_to_row(wi, eid, flow_topic_id, at)

    socket
    |> stream_insert(:workitems, row)
    |> track_workitem(row)
  end

  defp apply_workitem(socket, %RunnerWorkitem{id: id}, _eid, _flow_topic_id, _at) do
    drop_workitem(socket, id)
  end

  defp track_workitem(socket, %WorkitemRow{id: id, enactment_id: eid, state: state}) do
    index = socket.assigns.enactment_workitems
    next_index = Map.update(index, eid, MapSet.new([id]), &MapSet.put(&1, id))

    state_index = Map.put(socket.assigns.workitem_states, id, state)

    socket
    |> assign(:enactment_workitems, next_index)
    |> assign(:workitem_states, state_index)
    |> recompute_counts(next_index, state_index)
  end

  defp drop_workitem(socket, id) do
    index = socket.assigns.enactment_workitems
    state_index = socket.assigns.workitem_states

    {next_index, next_state_index} = remove_from_indices(index, state_index, id)

    socket
    |> stream_delete_by_item_key(:workitems, id)
    |> assign(:enactment_workitems, next_index)
    |> assign(:workitem_states, next_state_index)
    |> recompute_counts(next_index, next_state_index)
  end

  defp remove_from_indices(index, state_index, id) do
    state_index = Map.delete(state_index, id)

    next_index =
      Enum.reduce(index, %{}, fn {eid, ids}, acc ->
        remaining = MapSet.delete(ids, id)

        if Enum.empty?(remaining) do
          acc
        else
          Map.put(acc, eid, remaining)
        end
      end)

    {next_index, state_index}
  end

  defp recompute_counts(socket, index, state_index) do
    by_state = state_index |> Map.values() |> Enum.frequencies()

    counts = %InboxCounts{
      enabled: Map.get(by_state, :enabled, 0),
      started: Map.get(by_state, :started, 0),
      by_enactment: Map.new(index, fn {eid, ids} -> {eid, MapSet.size(ids)} end)
    }

    assign(socket, :counts, counts)
  end

  # ---------------------------------------------------------------------------
  # Row builders
  # ---------------------------------------------------------------------------

  defp schema_to_row(%Schemas.Workitem{} = w, flow_cache) do
    %WorkitemRow{
      id: w.id,
      enactment_id: w.enactment_id,
      flow_topic_id: resolve_flow_topic_id(w.enactment_id, flow_cache),
      transition: transition_label(w.binding_element),
      state: w.state,
      binding_summary: format_binding(w.binding_element),
      enabled_at: datetime_to_iso(w.inserted_at),
      updated_at: datetime_to_iso(w.updated_at)
    }
  end

  defp runtime_to_row(%RunnerWorkitem{} = wi, eid, flow_topic_id, %DateTime{} = at) do
    iso = DateTime.to_iso8601(at)

    %WorkitemRow{
      id: wi.id,
      enactment_id: eid,
      flow_topic_id: flow_topic_id,
      transition: transition_label(wi.binding_element),
      state: wi.state,
      binding_summary: format_binding(wi.binding_element),
      enabled_at: iso,
      updated_at: iso
    }
  end

  defp transition_label(%BindingElement{transition: transition}), do: to_string(transition)

  defp format_binding(%BindingElement{binding: binding}) do
    Enum.map_join(binding, ", ", fn {name, value} -> "#{name} = #{inspect(value)}" end)
  end

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
end
