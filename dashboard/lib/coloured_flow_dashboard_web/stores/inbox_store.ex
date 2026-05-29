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

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Runner.Enactment.Workitem, as: RunnerWorkitem
  alias ColouredFlow.Runner.Enactment.WorkitemTransition
  alias ColouredFlow.Runner.Exceptions.InvalidWorkitemTransition
  alias ColouredFlow.Runner.Exceptions.NonLiveWorkitem
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
            | :runner_error
    end
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
      |> assign(:workitem_meta, build_meta_index(rows))
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
  # the entry whenever a workitem appears or transitions state.
  defp build_meta_index(rows) do
    Map.new(rows, fn %WorkitemRow{id: id, enactment_id: eid, transition: name} ->
      {id, %{enactment_id: eid, transition: name}}
    end)
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

    Enum.reduce(ids, socket, &drop_workitem(&2, &1))
  end

  defp route_event(%Event{}, socket), do: socket

  defp apply_workitem(
         socket,
         %RunnerWorkitem{state: state} = wi,
         eid,
         flow_topic_id,
         at,
         flow_cache
       )
       when state in @live_states do
    row = runtime_to_row(wi, eid, flow_topic_id, at, flow_cache)

    socket
    |> stream_insert(:workitems, row)
    |> track_workitem(row)
  end

  defp apply_workitem(socket, %RunnerWorkitem{id: id}, _eid, _flow_topic_id, _at, _flow_cache) do
    drop_workitem(socket, id)
  end

  defp track_workitem(socket, %WorkitemRow{
         id: id,
         enactment_id: eid,
         state: state,
         transition: name
       }) do
    index = socket.assigns.enactment_workitems
    next_index = Map.update(index, eid, MapSet.new([id]), &MapSet.put(&1, id))

    state_index = Map.put(socket.assigns.workitem_states, id, state)
    meta_index = Map.put(socket.assigns.workitem_meta, id, %{enactment_id: eid, transition: name})

    socket
    |> assign(:enactment_workitems, next_index)
    |> assign(:workitem_states, state_index)
    |> assign(:workitem_meta, meta_index)
    |> recompute_counts(next_index, state_index)
  end

  defp drop_workitem(socket, id) do
    index = socket.assigns.enactment_workitems
    state_index = socket.assigns.workitem_states
    meta_index = socket.assigns.workitem_meta

    {next_index, next_state_index, next_meta_index} =
      remove_from_indices(index, state_index, meta_index, id)

    socket
    |> stream_delete_by_item_key(:workitems, id)
    |> assign(:enactment_workitems, next_index)
    |> assign(:workitem_states, next_state_index)
    |> assign(:workitem_meta, next_meta_index)
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
      binding_summary: format_binding(w.binding_element),
      output_vars: resolve_output_vars(w.enactment_id, w.binding_element, flow_cache),
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
      binding_summary: format_binding(wi.binding_element),
      output_vars: resolve_output_vars(eid, wi.binding_element, flow_cache),
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

  # Walks the per-transition `Action.outputs` list — auto-populated by
  # `ColouredFlow.Builder.SetActionOutputs` as
  # `output_arc_vars MINUS input_arc_vars MINUS constants` — to surface the
  # free-variable names the operator must supply in the outputs drawer.
  #
  # Falls back to `[]` when the bridge cache misses (no Repo / enactment row
  # not yet visible to storage) — the drawer renders an empty hint and the
  # operator can still type raw JSON. The command handler re-resolves at
  # dispatch time, so the missing hint never causes a wrong dispatch.
  @spec resolve_output_vars(String.t(), BindingElement.t(), atom() | nil) :: [String.t()]
  defp resolve_output_vars(enactment_id, %BindingElement{transition: transition}, flow_cache)
       when is_binary(enactment_id) and is_atom(flow_cache) and not is_nil(flow_cache) do
    with {:ok, %ColouredPetriNet{} = cpnet} <- fetch_cpnet(enactment_id, flow_cache),
         %Transition{action: %Action{outputs: outputs}} <- find_transition(cpnet, transition) do
      Enum.map(outputs, &Atom.to_string/1)
    else
      _miss -> []
    end
  end

  defp resolve_output_vars(_eid, _binding_element, _cache), do: []

  defp fetch_cpnet(enactment_id, flow_cache) do
    case :ets.whereis(flow_cache) do
      :undefined -> :error
      _table -> TelemetryBridge.lookup_cpnet(enactment_id, flow_cache)
    end
  end

  defp find_transition(%ColouredPetriNet{transitions: transitions}, transition_name)
       when is_binary(transition_name) do
    Enum.find(transitions, fn %Transition{name: name} -> name == transition_name end)
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
  #   :runner_error        — any other exception from the runner — reason
  #                          surfaced in `:message` for debugging.

  defp complete_workitem_reply(workitem_id, outputs_json, socket) do
    with {:ok, %{enactment_id: eid}} <- fetch_meta(workitem_id, socket),
         {:ok, outputs_map} <- ensure_map(outputs_json),
         {:ok, free_binding} <- coerce_outputs(outputs_map) do
      dispatch_completion(eid, workitem_id, free_binding)
    else
      {:error, :unknown_workitem} ->
        %{code: :unknown_workitem, workitem_id: workitem_id}

      {:error, {:unknown_variable, key}} ->
        %{code: :unknown_variable, variable: key}

      {:error, :invalid_outputs} ->
        %{code: :invalid_outputs, message: "outputs must be a JSON object"}
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

  defp coerce_outputs(outputs_map) do
    Enum.reduce_while(outputs_map, {:ok, []}, fn {key, value}, {:ok, acc} ->
      case to_existing_atom_safe(key) do
        {:ok, atom} -> {:cont, {:ok, [{atom, value} | acc]}}
        :error -> {:halt, {:error, {:unknown_variable, to_string(key)}}}
      end
    end)
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
