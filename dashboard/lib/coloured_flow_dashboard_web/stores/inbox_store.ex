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
  | `:enactment_exception`                                     | mark enactment `:exception`; re-emit tracked rows   |
  | `:enactment_start`                                         | mark enactment `:running`; re-emit tracked rows     |
  | everything else (lifecycle starts, take_snapshot, op `:start`/`:exception` halves) | no-op (counts unchanged)            |

  Per-event payloads are treated as eventually consistent: a `cf:flow:<id>`
  side-effect may have been skipped by the bridge on storage-lookup
  failure, so `flow_topic_id` is best-effort and may be `nil` even after
  the corresponding `cf:inbox` event has been observed.
  """

  use Musubi.Store, root: true

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Runner.Enactment.Workitem, as: RunnerWorkitem
  alias ColouredFlow.Runner.Enactment.WorkitemTransition
  alias ColouredFlow.Runner.Exceptions.InvalidWorkitemTransition
  alias ColouredFlow.Runner.Exceptions.NonLiveWorkitem
  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlow.Runner.Worklist.WorkitemStream
  alias ColouredFlowDashboard.OutputSchemaBuilder
  alias ColouredFlowDashboard.Repo
  alias ColouredFlowDashboard.TelemetryBridge
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboardWeb.Views.InboxCounts
  alias ColouredFlowDashboardWeb.Views.OutputVar
  alias ColouredFlowDashboardWeb.Views.WorkitemRow

  import Ecto.Query, only: [from: 2]

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

  # The drawer dispatches `outputs` as a JSON object (string keys). The
  # `:outputs` field is typed `map()` so the wire schema validator accepts
  # an arbitrary `Record<string, unknown>` from the client; `handle_command/3`
  # coerces it into the runner's `[{atom, term}]` shape.
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
            | :runner_error
    end
  end

  @impl Musubi.Store
  def mount(params, socket) when is_map(params) do
    pubsub = Map.get(params, "pubsub_name", @default_pubsub)
    topic = Map.get(params, "topic", @default_topic)
    flow_cache = Map.get(params, "flow_cache", @default_flow_cache)

    :ok = Phoenix.PubSub.subscribe(pubsub, topic)

    raw_rows = seed_rows(flow_cache)
    enactment_states = seed_enactment_states(raw_rows)
    rows = Enum.map(raw_rows, &stamp_enactment_state(&1, enactment_states))
    enactment_index = build_enactment_index(rows)
    counts = compute_counts(rows, enactment_index)

    socket =
      socket
      |> assign(:pubsub_name, pubsub)
      |> assign(:topic, topic)
      |> assign(:flow_cache, flow_cache)
      |> assign(:enactment_workitems, enactment_index)
      |> assign(:workitem_states, build_state_index(rows))
      |> assign(:workitem_meta, build_meta_index(rows))
      |> assign(:workitem_rows, build_row_index(rows))
      |> assign(:enactment_states, enactment_states)
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

  @impl Musubi.Store
  def handle_command(:complete_workitem, payload, socket) when is_map(payload) do
    workitem_id = Map.get(payload, "workitem_id") || Map.get(payload, :workitem_id)
    outputs_json = Map.get(payload, "outputs") || Map.get(payload, :outputs)

    {:reply, complete_workitem_reply(workitem_id, outputs_json, socket), socket}
  end

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

  # `:complete_workitem` needs to map a bare workitem id back to its
  # enactment + transition without re-querying storage. The mount seed
  # supplies both directly from `WorkitemRow`; live PubSub events refresh
  # the entry whenever a workitem appears or transitions state. The schema
  # map (`%{var_name :: String.t() => OutputVar.t()}`) is stored alongside
  # so the command handler can coerce typed values without re-walking the
  # cpnet.
  defp build_meta_index(rows) do
    Map.new(rows, fn %WorkitemRow{
                       id: id,
                       enactment_id: eid,
                       transition: name,
                       output_vars: schema
                     } ->
      {id, %{enactment_id: eid, transition: name, schema: index_schema(schema)}}
    end)
  end

  defp index_schema(schema) when is_list(schema) do
    Map.new(schema, fn %OutputVar{name: name} = var -> {name, var} end)
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
      apply_workitem(acc, wi, eid, flow_topic_id, at, flow_cache)
    end)
  end

  defp route_event(%Event{kind: :enactment_terminate, enactment_id: eid}, socket) do
    ids = Map.get(socket.assigns.enactment_workitems, eid, MapSet.new())

    socket
    |> set_enactment_state(eid, :terminated)
    |> then(fn s -> Enum.reduce(ids, s, &drop_workitem(&2, &1)) end)
  end

  defp route_event(%Event{kind: :enactment_exception, enactment_id: eid}, socket) do
    socket
    |> set_enactment_state(eid, :exception)
    |> restamp_rows_for(eid)
  end

  defp route_event(%Event{kind: :enactment_start, enactment_id: eid}, socket) do
    socket
    |> set_enactment_state(eid, :running)
    |> restamp_rows_for(eid)
  end

  defp route_event(%Event{}, socket), do: socket

  defp set_enactment_state(socket, eid, new_state) do
    assign(socket, :enactment_states, Map.put(socket.assigns.enactment_states, eid, new_state))
  end

  # Re-emit every tracked row for `eid` with the freshly-stamped
  # `enactment_state`. Stream key is the workitem id, so the upsert flips
  # the field in-place without duplicating rows.
  defp restamp_rows_for(socket, eid) do
    ids = Map.get(socket.assigns.enactment_workitems, eid, MapSet.new())
    enactment_state = Map.get(socket.assigns.enactment_states, eid, :running)

    Enum.reduce(ids, socket, fn id, acc ->
      case Map.get(acc.assigns.workitem_rows, id) do
        %WorkitemRow{} = row -> restamp_row(acc, id, %{row | enactment_state: enactment_state})
        nil -> acc
      end
    end)
  end

  defp restamp_row(socket, id, %WorkitemRow{} = row) do
    rows = Map.put(socket.assigns.workitem_rows, id, row)

    socket
    |> stream_insert(:workitems, row)
    |> assign(:workitem_rows, rows)
  end

  defp apply_workitem(
         socket,
         %RunnerWorkitem{state: state} = wi,
         eid,
         flow_topic_id,
         at,
         flow_cache
       )
       when state in @live_states do
    row =
      wi
      |> runtime_to_row(eid, flow_topic_id, at, flow_cache)
      |> stamp_enactment_state(socket.assigns.enactment_states)

    socket
    |> stream_insert(:workitems, row)
    |> track_workitem(row)
  end

  defp apply_workitem(socket, %RunnerWorkitem{id: id}, _eid, _flow_topic_id, _at, _flow_cache) do
    drop_workitem(socket, id)
  end

  defp track_workitem(
         socket,
         %WorkitemRow{
           id: id,
           enactment_id: eid,
           state: state,
           transition: name,
           output_vars: schema
         } = row
       ) do
    index = socket.assigns.enactment_workitems
    next_index = Map.update(index, eid, MapSet.new([id]), &MapSet.put(&1, id))

    state_index = Map.put(socket.assigns.workitem_states, id, state)

    meta_index =
      Map.put(
        socket.assigns.workitem_meta,
        id,
        %{enactment_id: eid, transition: name, schema: index_schema(schema)}
      )

    row_index = Map.put(socket.assigns.workitem_rows, id, row)

    socket
    |> assign(:enactment_workitems, next_index)
    |> assign(:workitem_states, state_index)
    |> assign(:workitem_meta, meta_index)
    |> assign(:workitem_rows, row_index)
    |> recompute_counts(next_index, state_index)
  end

  defp drop_workitem(socket, id) do
    index = socket.assigns.enactment_workitems
    state_index = socket.assigns.workitem_states
    meta_index = socket.assigns.workitem_meta
    row_index = socket.assigns.workitem_rows

    {next_index, next_state_index, next_meta_index} =
      remove_from_indices(index, state_index, meta_index, id)

    socket
    |> stream_delete_by_item_key(:workitems, id)
    |> assign(:enactment_workitems, next_index)
    |> assign(:workitem_states, next_state_index)
    |> assign(:workitem_meta, next_meta_index)
    |> assign(:workitem_rows, Map.delete(row_index, id))
    |> recompute_counts(next_index, next_state_index)
  end

  defp remove_from_indices(index, state_index, meta_index, id) do
    state_index = Map.delete(state_index, id)
    meta_index = Map.delete(meta_index, id)

    next_index =
      Enum.reduce(index, %{}, fn {eid, ids}, acc ->
        remaining = MapSet.delete(ids, id)

        if Enum.empty?(remaining) do
          acc
        else
          Map.put(acc, eid, remaining)
        end
      end)

    {next_index, state_index, meta_index}
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
      enactment_state: :running,
      binding_summary: format_binding(w.binding_element),
      output_vars: resolve_output_schema(w.enactment_id, w.binding_element, flow_cache),
      enabled_at: datetime_to_iso(w.inserted_at),
      updated_at: datetime_to_iso(w.updated_at)
    }
  end

  defp runtime_to_row(%RunnerWorkitem{} = wi, eid, flow_topic_id, %DateTime{} = at, flow_cache) do
    iso = DateTime.to_iso8601(at)

    %WorkitemRow{
      id: wi.id,
      enactment_id: eid,
      flow_topic_id: flow_topic_id,
      transition: transition_label(wi.binding_element),
      state: wi.state,
      enactment_state: :running,
      binding_summary: format_binding(wi.binding_element),
      output_vars: resolve_output_schema(eid, wi.binding_element, flow_cache),
      enabled_at: iso,
      updated_at: iso
    }
  end

  defp stamp_enactment_state(%WorkitemRow{enactment_id: eid} = row, state_map) do
    %WorkitemRow{row | enactment_state: Map.get(state_map, eid, :running)}
  end

  defp build_row_index(rows) do
    Map.new(rows, fn %WorkitemRow{id: id} = row -> {id, row} end)
  end

  # Bulk-loads non-`:running` states for every enactment present in `rows`.
  # We seed an enactment as `:running` by default and overwrite only when
  # the DB row says otherwise — keeps the query result-set small (typically
  # zero in healthy fleets) AND keeps the no-Repo path a single branch.
  defp seed_enactment_states(rows) do
    eids =
      rows
      |> Enum.map(& &1.enactment_id)
      |> Enum.uniq()

    cond do
      eids == [] -> %{}
      not repo_configured?() -> %{}
      true -> query_enactment_states(eids)
    end
  end

  defp query_enactment_states(eids) do
    query =
      from(e in Schemas.Enactment,
        where: e.id in ^eids and e.state != ^:running,
        select: {e.id, e.state}
      )

    query |> Repo.all() |> Map.new()
  rescue
    _error -> %{}
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

  # Walks the per-transition `Action.outputs` list — auto-populated by
  # `ColouredFlow.Builder.SetActionOutputs` as
  # `output_arc_vars MINUS input_arc_vars MINUS constants` — and pairs each
  # free variable with its colour-set descriptor via
  # `OutputSchemaBuilder.build/2`, producing a list of `OutputVar.t()` for the
  # structured drawer form.
  #
  # Falls back to `[]` when the bridge cache misses (no Repo / enactment row
  # not yet visible to storage) — the drawer renders an empty hint and the
  # operator can still type raw JSON in the fallback Textarea. The command
  # handler re-resolves at dispatch time, so the missing hint never causes a
  # wrong dispatch.
  @spec resolve_output_schema(String.t(), BindingElement.t(), atom() | nil) :: [OutputVar.t()]
  defp resolve_output_schema(enactment_id, %BindingElement{transition: transition}, flow_cache)
       when is_binary(enactment_id) and is_atom(flow_cache) and not is_nil(flow_cache) do
    case fetch_cpnet(enactment_id, flow_cache) do
      {:ok, %ColouredPetriNet{} = cpnet} -> OutputSchemaBuilder.build(cpnet, transition)
      :error -> []
    end
  end

  defp resolve_output_schema(_eid, _binding_element, _cache), do: []

  defp fetch_cpnet(enactment_id, flow_cache) do
    case :ets.whereis(flow_cache) do
      :undefined -> :error
      _table -> TelemetryBridge.lookup_cpnet(enactment_id, flow_cache)
    end
  end

  # ---------------------------------------------------------------------------
  # :complete_workitem command
  # ---------------------------------------------------------------------------
  #
  # Reply codes (caller atom; Wire emits the string form):
  #
  #   :ok                  — runner accepted the completion. The PubSub-driven
  #                          `:complete_workitems_stop` event will drive the
  #                          stream delete asynchronously; the handler MUST NOT
  #                          also call `stream_delete_by_item_key/3` here or
  #                          the delete would be emitted twice.
  #   :already_completed   — workitem id no longer live (completed/withdrawn).
  #                          Runner returns `InvalidWorkitemTransition` or
  #                          `NonLiveWorkitem`; both flatten to this code.
  #   :unknown_workitem    — id not tracked in the store (stale row on the
  #                          client, or never seen on this page).
  #   :unknown_variable    — operator submitted a key that does not exist as
  #                          an atom anywhere in the BEAM; `to_existing_atom/1`
  #                          rejected it before reaching the runner.
  #   :invalid_outputs     — payload's `outputs` field was not a JSON object.
  #   :type_mismatch       — the operator supplied a value whose wire shape
  #                          does not match the declared colour-set kind
  #                          (e.g. a string where the schema expected an
  #                          integer, or an enum value not in `enum_values`).
  #                          Reply carries `:variable` + `:expected_kind` so
  #                          the SPA can pin a field-level error.
  #   :runner_error        — any other exception from the runner — reason
  #                          surfaced in `:message` for debugging.

  defp complete_workitem_reply(workitem_id, outputs_json, socket) do
    with {:ok, meta} <- fetch_meta(workitem_id, socket),
         {:ok, outputs_map} <- ensure_map(outputs_json),
         {:ok, free_binding} <- coerce_outputs(outputs_map, meta.schema) do
      dispatch_completion(meta.enactment_id, workitem_id, free_binding)
    else
      {:error, :unknown_workitem} ->
        %{code: :unknown_workitem, workitem_id: workitem_id}

      {:error, {:unknown_variable, key}} ->
        %{code: :unknown_variable, variable: key}

      {:error, :invalid_outputs} ->
        %{code: :invalid_outputs, message: "outputs must be a JSON object"}

      {:error, {:type_mismatch, key, expected}} ->
        %{
          code: :type_mismatch,
          variable: key,
          expected_kind: expected,
          message: "Output `#{key}` must be a #{expected}."
        }

      {:error, {:unknown_enum, key, value}} ->
        %{
          code: :type_mismatch,
          variable: key,
          expected_kind: "enum",
          message: "Output `#{key}` does not accept value #{inspect(value)}."
        }
    end
  end

  defp fetch_meta(workitem_id, socket) when is_binary(workitem_id) do
    case Map.fetch(socket.assigns.workitem_meta, workitem_id) do
      {:ok, meta} -> {:ok, meta}
      :error -> {:error, :unknown_workitem}
    end
  end

  defp fetch_meta(_other, _socket), do: {:error, :unknown_workitem}

  defp ensure_map(map) when is_map(map), do: {:ok, map}
  defp ensure_map(_other), do: {:error, :invalid_outputs}

  defp coerce_outputs(outputs_map, schema) when is_map(outputs_map) and is_map(schema) do
    Enum.reduce_while(outputs_map, {:ok, []}, fn {key, value}, {:ok, acc} ->
      key_str = to_string(key)

      with {:ok, atom} <- to_existing_atom_safe(key),
           {:ok, coerced} <- coerce_one(Map.get(schema, key_str), key_str, value) do
        {:cont, {:ok, [{atom, coerced} | acc]}}
      else
        :error ->
          {:halt, {:error, {:unknown_variable, key_str}}}

        {:error, {:type_mismatch, expected}} ->
          {:halt, {:error, {:type_mismatch, key_str, expected}}}

        {:error, {:unknown_enum, value}} ->
          {:halt, {:error, {:unknown_enum, key_str, value}}}
      end
    end)
  end

  defp coerce_one(schema_var, _key, value) do
    OutputSchemaBuilder.coerce_value(schema_var, value)
  end

  defp to_existing_atom_safe(key) when is_atom(key), do: {:ok, key}

  defp to_existing_atom_safe(key) when is_binary(key) do
    {:ok, String.to_existing_atom(key)}
  rescue
    ArgumentError -> :error
  end

  defp to_existing_atom_safe(_other), do: :error

  defp dispatch_completion(enactment_id, workitem_id, free_binding) do
    case WorkitemTransition.complete_workitem(enactment_id, {workitem_id, free_binding}) do
      {:ok, %RunnerWorkitem{}} ->
        %{code: :ok}

      {:error, %InvalidWorkitemTransition{}} ->
        %{code: :already_completed, workitem_id: workitem_id}

      {:error, %NonLiveWorkitem{}} ->
        %{code: :already_completed, workitem_id: workitem_id}

      {:error, exception} when is_exception(exception) ->
        %{code: :runner_error, message: Exception.message(exception)}
    end
  catch
    :exit, {:noproc, _info} -> %{code: :already_completed, workitem_id: workitem_id}
    kind, reason -> %{code: :runner_error, message: Exception.format(kind, reason)}
  end
end
