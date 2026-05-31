defmodule ColouredFlowDashboardWeb.Stores.TelemetryFeedStore do
  @moduledoc """
  Root Musubi store backing the global runner telemetry feed at `/telemetry`.

  Singleton — the SPA mounts a single instance via:

      useMusubiRootSuspense({
        module: "ColouredFlowDashboardWeb.Stores.TelemetryFeedStore",
        id: "global"
      })

  ## State

    * `:entries` stream — `GlobalTelemetryEntry` per accepted bridge event.
      Capped at `@window` (default `500`). Newer entries push older entries
      out of the window via explicit `stream_delete_by_item_key/3` calls so
      the server-side memory footprint stays bounded (Musubi's `:limit`
      is client-side only).
    * `:total_events` — running tally of every accepted event since mount.
      Distinct from the window size: events older than the cap stay
      counted here.
    * `:entries_in_window` — current size of the bounded window.
    * `:oldest_seq` / `:newest_seq` — bridge seq endpoints for the
      entries currently in the window. `nil` when the window is empty.

  ## Event routing

  Subscribes to `cf:telemetry`. Every `%Event{}` arriving on that topic is
  accepted (including event halves the per-enactment store filters out).
  Per-enactment seq is still honoured via `SeqTracker` so a late event
  cannot leapfrog a newer one for the same enactment id.

  Mount subscribes first, then backfills from the bridge-owned ETS events
  buffer through the same `ingest_event/2` path used for live PubSub events.
  That keeps ordering, stale-drop, and window trimming identical across the
  replay and live phases.

  Read-only — no commands. The operator inspects the feed; submitting
  outputs and other state mutation happens on the per-enactment surfaces.
  """

  use Musubi.Store, root: true

  alias ColouredFlowDashboard.TelemetryBridge
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboardWeb.Stores.SeqTracker
  alias ColouredFlowDashboardWeb.Views.GlobalTelemetryEntry

  require Logger

  @default_pubsub :coloured_flow_dashboard_pubsub
  @default_topic "cf:telemetry"
  @default_flow_cache :coloured_flow_dashboard_telemetry_bridge_flow_cache
  @default_events_buffer :coloured_flow_dashboard_telemetry_bridge_events_buffer
  @window 500

  state do
    stream :entries, ColouredFlowDashboardWeb.Views.GlobalTelemetryEntry.t(),
      limit: @window,
      item_key: & &1.id

    field :total_events, integer()
    field :entries_in_window, integer()
    field :oldest_seq, integer() | nil
    field :newest_seq, integer() | nil
  end

  @impl Musubi.Store
  def mount(params, socket) when is_map(params) do
    pubsub = Map.get(params, "pubsub_name", @default_pubsub)
    topic = Map.get(params, "topic", @default_topic)
    flow_cache = Map.get(params, "flow_cache", @default_flow_cache)
    events_buffer = Map.get(params, "events_buffer", @default_events_buffer)
    window = Map.get(params, "window", @window)

    :ok = Phoenix.PubSub.subscribe(pubsub, topic)

    socket =
      socket
      |> assign(:pubsub_name, pubsub)
      |> assign(:topic, topic)
      |> assign(:flow_cache, flow_cache)
      |> assign(:events_buffer, events_buffer)
      |> assign(:window, window)
      |> assign(:total_events, 0)
      |> assign(:entries_in_window, 0)
      |> assign(:oldest_seq, nil)
      |> assign(:newest_seq, nil)
      |> assign(:last_seq, %{})
      # Ordered `[{id, seq}]` list — newest (highest seq) at head, matching
      # the stream's `at: 0` insertion semantics. Position-based insert keeps
      # the feed sorted by bridge seq even when the bridge's per-event Task
      # fan-out lets cross-enactment events arrive out of seq order.
      # Musubi's `:limit` is client-side only so the server tracks its own
      # bound + trims the tail on overflow.
      |> assign(:entries_index, [])
      |> stream(:entries, [], reset: true)

    socket =
      Enum.reduce(TelemetryBridge.recent_events(events_buffer), socket, fn event, acc ->
        if SeqTracker.stale?(event, acc.assigns.last_seq) do
          acc
        else
          acc
          |> assign(:last_seq, SeqTracker.bump(acc.assigns.last_seq, event))
          |> ingest_event(event)
        end
      end)

    {:ok, socket}
  end

  @impl Musubi.Store
  def render(socket) do
    # Musubi's `assign/3` short-circuits when the new value equals the
    # previous value AND skips the assign altogether when the new value is
    # `nil` and the slot was never seeded. Read through `Map.get/2` so the
    # initial `nil` for seq endpoints surfaces correctly.
    %{
      entries: stream(:entries),
      total_events: socket.assigns.total_events,
      entries_in_window: socket.assigns.entries_in_window,
      oldest_seq: Map.get(socket.assigns, :oldest_seq),
      newest_seq: Map.get(socket.assigns, :newest_seq)
    }
  end

  @impl Musubi.Store
  def handle_info({:cf_event, %Event{} = event}, socket) do
    if SeqTracker.stale?(event, socket.assigns.last_seq) do
      {:noreply, socket}
    else
      socket =
        socket
        |> assign(:last_seq, SeqTracker.bump(socket.assigns.last_seq, event))
        |> ingest_event(event)

      {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl Musubi.Store
  def handle_command(_name, _payload, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Ingest
  # ---------------------------------------------------------------------------

  defp ingest_event(socket, %Event{} = event) do
    entry = build_entry(event, socket.assigns.flow_cache)
    %GlobalTelemetryEntry{id: id} = entry
    seq = event.seq
    index = socket.assigns.entries_index
    position = insert_position(index, seq)
    next_index = List.insert_at(index, position, {id, seq})

    socket
    |> stream_insert(:entries, entry, at: position)
    |> assign(:entries_index, next_index)
    |> assign(:total_events, socket.assigns.total_events + 1)
    |> assign(:entries_in_window, length(next_index))
    |> assign(:newest_seq, head_seq(next_index))
    |> assign(:oldest_seq, tail_seq(next_index))
    |> trim_window()
  end

  # Newest entry sits at index 0, so walk the list head-first and count items
  # whose seq is greater-or-equal to the new one. Ties keep arrival order
  # (new event slots in after equal-seq predecessors). O(N) at the bounded
  # window of 500.
  defp insert_position(index, seq) do
    Enum.find_index(index, fn {_id, existing} -> existing < seq end) ||
      length(index)
  end

  defp trim_window(socket) do
    index = socket.assigns.entries_index
    window = socket.assigns.window

    if length(index) <= window do
      socket
    else
      {{drop_id, _drop_seq}, next_index} = List.pop_at(index, -1)

      socket
      |> stream_delete_by_item_key(:entries, drop_id)
      |> assign(:entries_index, next_index)
      |> assign(:entries_in_window, length(next_index))
      |> assign(:newest_seq, head_seq(next_index))
      |> assign(:oldest_seq, tail_seq(next_index))
      |> trim_window()
    end
  end

  defp head_seq([{_id, seq} | _rest]), do: seq
  defp head_seq([]), do: nil

  defp tail_seq([]), do: nil
  defp tail_seq(list), do: list |> List.last() |> elem(1)

  # ---------------------------------------------------------------------------
  # Entry build
  # ---------------------------------------------------------------------------

  defp build_entry(%Event{} = event, flow_cache) do
    %GlobalTelemetryEntry{
      id: synthesize_id(),
      event: Atom.to_string(event.kind),
      enactment_id: enactment_id_field(event),
      flow_id: resolve_flow_id(event, flow_cache),
      occurred_at: datetime_to_iso(event.occurred_at),
      seq: event.seq,
      measurements_json: encode_json(measurements_payload(event)),
      metadata_json: encode_json(metadata_payload(event)),
      summary: derive_summary(event)
    }
  end

  defp synthesize_id, do: "tf-#{System.unique_integer([:positive, :monotonic])}"

  defp enactment_id_field(%Event{enactment_id: id}) when is_binary(id), do: id

  defp resolve_flow_id(%Event{enactment_id: id}, flow_cache)
       when is_binary(id) and is_atom(flow_cache) and not is_nil(flow_cache) do
    case :ets.whereis(flow_cache) do
      :undefined ->
        nil

      _table ->
        case TelemetryBridge.lookup_flow_topic_id(id, flow_cache) do
          {:ok, flow_id} -> flow_id
          :error -> nil
        end
    end
  end

  defp resolve_flow_id(_event, _cache), do: nil

  # Measurements view — surface the canonical timestamp + bridge sequence so
  # operators can correlate ordering at a glance without the bridge having
  # to round-trip raw `:telemetry` measurements (which would force the
  # bridge to forward maps it currently summarises and discards).
  defp measurements_payload(%Event{} = event) do
    %{
      "occurred_at" => datetime_to_iso(event.occurred_at),
      "seq" => event.seq,
      "enactment_version" => event.enactment_version
    }
  end

  # Metadata view — the bridge already serialises the runner's metadata
  # into `payload` plus the `markings_summary` / `workitems_summary` rollups
  # (with `%ColouredPetriNet{}` already trimmed off, since the bridge only
  # carries the runner state rollup). Re-expose them as a JSON-friendly
  # metadata blob so the SPA can render the raw context without each row
  # carrying a custom decoder.
  defp metadata_payload(%Event{} = event) do
    %{
      "kind" => Atom.to_string(event.kind),
      "payload" => sanitize_for_json(event.payload),
      "markings" => sanitize_for_json(event.markings_summary),
      "workitems" => sanitize_for_json(event.workitems_summary)
    }
  end

  defp encode_json(value) do
    JSON.encode!(value)
  rescue
    _error -> inspect_safe(value)
  end

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

  defp datetime_to_iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  # One-line summary for the collapsed row — the SPA always shows the raw
  # `event` string in the dedicated column; this gives a brief humanised
  # gloss for the description column so rows scan quickly.
  defp derive_summary(%Event{kind: kind, payload: payload}),
    do: summarize(kind, payload)

  defp summarize(:produce_workitems_stop, payload),
    do: "produced #{count_workitems(payload)} workitem(s)"

  defp summarize(:start_workitems_stop, payload),
    do: "started #{count_workitems(payload)} workitem(s)"

  defp summarize(:complete_workitems_stop, payload),
    do: "completed #{count_workitems(payload)} workitem(s)"

  defp summarize(:withdraw_workitems_stop, payload),
    do: "withdrew #{count_workitems(payload)} workitem(s)"

  defp summarize(:enactment_terminate, payload) do
    msg =
      Map.get(payload, :termination_message) ||
        Map.get(payload, :termination_type) ||
        "force"

    "terminated: #{inspect_safe(msg)}"
  end

  defp summarize(:enactment_exception, payload),
    do: Map.get(payload, :error_banner) || "exception"

  defp summarize(kind, _payload) when is_atom(kind), do: ""

  defp count_workitems(payload) when is_map(payload) do
    case Map.get(payload, :workitems) do
      list when is_list(list) -> length(list)
      _other -> 0
    end
  end
end
