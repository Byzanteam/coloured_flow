defmodule ColouredFlowDashboardWeb.Stores.FlowCatalogStore do
  @moduledoc """
  Root Musubi store backing the flow catalog at `/flows`.

  Lists every registered flow on mount, surfacing per-flow rollups (live
  enactment count, the 3 most recent enactments, last-started timestamp,
  static place / transition counts) so the SPA can render a "what flows can
  I run, and what is running already" overview without paginating.

  ## Mount params

  All optional; defaults match the production wiring.

    * `"pubsub_name"` — `Phoenix.PubSub` server name. Defaults to
      `:coloured_flow_dashboard_pubsub`.
    * `"topic"` — topic to subscribe to. Defaults to `"cf:flows"`.

  ## PubSub topic

  Subscribes to `"cf:flows"`. The bridge republishes enactment lifecycle
  events (`:enactment_start`, `:enactment_terminate`, `:enactment_exception`)
  to this topic so the catalog can refresh live counts as enactments come
  and go without polling storage.

  Per-enactment monotonic seq sequencing follows the same drop-stale
  pattern as `InboxStore` / `EnactmentDetailStore`.

  ## Commands

    * `:start_enactment` — params `%{flow_id: String.t()}`. Resolves the
      flow row, looks up the matching seeded module to obtain
      `initial_markings`, calls `Runner.Storage.insert_enactment/1` +
      `Runner.start_enactment/1`. Reply codes:
      `:ok` (carries the new `:enactment_id`),
      `:unknown_flow`, `:no_initial_markings`, `:storage_error`,
      `:runner_error`.

      Initial markings are sourced from the seeded flow modules
      (`#{inspect(__MODULE__)}.@seed_by_name`) rather than from the storage
      row, because the public storage surface does not expose per-flow
      initial markings — only per-enactment ones. Flow rows whose name
      does not match a seeded module reply `:no_initial_markings`; the
      SPA disables the Start button for those rows.

    * `:refresh_catalog` — no payload. Reloads the flow stream + counts
      against the current storage backend. Used by the SPA "Refresh" button
      and by `handle_info/2` on every matching lifecycle event so the
      catalog stays current without a full remount.

  ## Cross-backend listing

  The storage backend is read once per refresh through
  `Runner.Storage.__storage__/0` (same dispatch as `Seed`). The Default
  (Postgres / Ecto) backend reads `Repo.all(Schemas.Flow)` and a per-flow
  enactment rollup with a single `IN ?` query. The InMemory backend reads
  the public ETS tables that the `InMemory` GenServer owns
  (`Module.concat(InMemory, "Flow")` / `"Enactment"`).

  Both reads are parallel deviations to the two existing waived
  `Schemas.*` reads (`InboxStore.query_enactment_states/1` +
  `EnactmentDetailStore.authoritative_enactment_state/1`): there is no
  public `Runner.list_flows/0` / `Runner.list_enactments_by_flow/1`. The
  next epic upstreams those.
  """

  use Musubi.Store, root: true

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Runner
  alias ColouredFlow.Runner.Storage
  alias ColouredFlow.Runner.Storage.InMemory
  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlowDashboard.Repo
  alias ColouredFlowDashboard.Seeds.ApprovalFlow
  alias ColouredFlowDashboard.Seeds.IncidentTriageFlow
  alias ColouredFlowDashboard.Seeds.PiAgentFlow
  alias ColouredFlowDashboard.Seeds.TrafficLightFlow
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboardWeb.Stores.SeqTracker
  alias ColouredFlowDashboardWeb.Views.FlowCatalogCounts
  alias ColouredFlowDashboardWeb.Views.FlowDetail
  alias ColouredFlowDashboardWeb.Views.FlowEnactmentEntry
  alias ColouredFlowDashboardWeb.Views.FlowSummary
  alias ColouredFlowDashboardWeb.Views.NetDiagram
  alias ColouredFlowDashboardWeb.Views.NetDiagramArc
  alias ColouredFlowDashboardWeb.Views.NetDiagramPlace
  alias ColouredFlowDashboardWeb.Views.NetDiagramTransition

  require InMemory

  import Ecto.Query, only: [from: 2]

  require Logger

  @default_pubsub :coloured_flow_dashboard_pubsub
  @default_topic "cf:flows"
  @recent_limit 3
  @flow_limit 200
  @seeded_modules [ApprovalFlow, IncidentTriageFlow, TrafficLightFlow, PiAgentFlow]

  # Flow name → %{module, version, initial_markings} index. Built at
  # compile time so the runtime command path is a constant-time lookup.
  @seed_by_name for mod <- @seeded_modules,
                    into: %{},
                    do:
                      {mod.__cpn__(:name),
                       %{
                         module: mod,
                         version: mod.__cpn__(:version),
                         initial_markings: mod.__cpn__(:initial_markings)
                       }}

  state do
    stream :flows, ColouredFlowDashboardWeb.Views.FlowSummary.t(),
      limit: @flow_limit,
      item_key: & &1.id

    field :counts, ColouredFlowDashboardWeb.Views.FlowCatalogCounts.t()
  end

  command :start_enactment do
    payload do
      field :flow_id, String.t()
    end

    reply do
      field :code,
            :ok
            | :unknown_flow
            | :no_initial_markings
            | :storage_error
            | :runner_error

      field :enactment_id, String.t() | nil
    end
  end

  command :refresh_catalog do
    reply do
      field :code, :ok
    end
  end

  command :fetch_flow_detail do
    payload do
      field :flow_id, String.t()
    end

    reply do
      field :code, :ok | :not_found
      field :flow, ColouredFlowDashboardWeb.Views.FlowDetail.t() | nil
    end
  end

  @impl Musubi.Store
  def mount(params, socket) when is_map(params) do
    pubsub = Map.get(params, "pubsub_name", @default_pubsub)
    topic = Map.get(params, "topic", @default_topic)

    :ok = Phoenix.PubSub.subscribe(pubsub, topic)

    %{flows: rows, counts: counts, ids: ids} = load_world()

    socket =
      socket
      |> assign(:pubsub_name, pubsub)
      |> assign(:topic, topic)
      |> assign(:counts, counts)
      |> assign(:flow_ids, ids)
      |> assign(:last_seq, %{})
      |> stream(:flows, rows, reset: true)

    {:ok, socket}
  end

  @impl Musubi.Store
  def render(socket) do
    %{flows: stream(:flows), counts: socket.assigns.counts}
  end

  @impl Musubi.Store
  def handle_command(:start_enactment, payload, socket) when is_map(payload) do
    flow_id = Map.get(payload, "flow_id") || Map.get(payload, :flow_id)
    {:reply, start_enactment_reply(flow_id), socket}
  end

  def handle_command(:refresh_catalog, _payload, socket) do
    {:reply, %{code: :ok}, refresh_socket(socket)}
  end

  def handle_command(:fetch_flow_detail, payload, socket) when is_map(payload) do
    flow_id = Map.get(payload, "flow_id") || Map.get(payload, :flow_id)
    {:reply, fetch_flow_detail_reply(flow_id), socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}

  @impl Musubi.Store
  def handle_info({:cf_event, %Event{} = event}, socket) do
    cond do
      not catalog_event?(event) ->
        {:noreply, socket}

      SeqTracker.stale?(event, socket.assigns.last_seq) ->
        {:noreply, socket}

      true ->
        socket = assign(socket, :last_seq, SeqTracker.bump(socket.assigns.last_seq, event))
        {:noreply, refresh_socket(socket)}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  # Only lifecycle events change the catalog rollups. Workitem-op events
  # would force a full rebuild on every operator click and add nothing —
  # the catalog does not track per-workitem state.
  defp catalog_event?(%Event{kind: kind})
       when kind in [:enactment_start, :enactment_terminate, :enactment_exception],
       do: true

  defp catalog_event?(%Event{}), do: false

  defp refresh_socket(socket) do
    %{flows: rows, counts: counts, ids: ids} = load_world()
    prev_ids = socket.assigns.flow_ids

    # Drop stream entries for flows that have disappeared from storage so
    # the client side cannot hold a ghost catalog row.
    socket =
      Enum.reduce(MapSet.difference(prev_ids, ids), socket, fn id, acc ->
        stream_delete_by_item_key(acc, :flows, id)
      end)

    socket =
      Enum.reduce(rows, socket, fn %FlowSummary{} = row, acc ->
        stream_insert(acc, :flows, row)
      end)

    socket
    |> assign(:flow_ids, ids)
    |> assign(:counts, counts)
  end

  # ---------------------------------------------------------------------------
  # Loading
  # ---------------------------------------------------------------------------

  defp load_world do
    flows = list_flow_rows()
    enactments_by_flow = list_enactments_by_flow(Enum.map(flows, & &1.id))

    rows =
      Enum.map(flows, fn flow ->
        build_summary(flow, Map.get(enactments_by_flow, flow.id, []))
      end)

    counts = compute_counts(rows)
    ids = MapSet.new(Enum.map(rows, & &1.id))

    %{flows: rows, counts: counts, ids: ids}
  end

  defp build_summary(%{id: id, name: name, definition: %ColouredPetriNet{} = cpnet}, enactments) do
    %{
      seed: seed,
      live: live,
      last_started_at: last_started_at,
      full_entries: full_entries
    } = enactment_rollup(name, enactments)

    %FlowSummary{
      id: id,
      name: name,
      version: if(seed, do: seed.version, else: ""),
      place_count: length(cpnet.places),
      transition_count: length(cpnet.transitions),
      live_enactments: live,
      total_enactments: length(full_entries),
      last_started_at: last_started_at,
      recent_enactments: Enum.take(full_entries, @recent_limit)
    }
  end

  defp build_detail(%{id: id, name: name, definition: %ColouredPetriNet{} = cpnet}, enactments) do
    %{
      seed: seed,
      live: live,
      last_started_at: last_started_at,
      full_entries: full_entries
    } = enactment_rollup(name, enactments)

    %FlowDetail{
      id: id,
      name: name,
      version: if(seed, do: seed.version, else: ""),
      place_count: length(cpnet.places),
      transition_count: length(cpnet.transitions),
      live_enactments: live,
      total_enactments: length(full_entries),
      last_started_at: last_started_at,
      enactments: full_entries,
      diagram: build_diagram(cpnet)
    }
  end

  defp enactment_rollup(name, enactments) do
    seed = Map.get(@seed_by_name, name)
    live = Enum.count(enactments, &(&1.state == :running))

    last_started_at =
      enactments
      |> Enum.map(& &1.inserted_at)
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        list -> list |> Enum.max(DateTime, fn -> nil end) |> datetime_to_iso()
      end

    # InMemory backend stores no inserted_at column, so nil is a valid value
    # across the rollup. `DateTime.compare/2` rejects nil; bucket nil rows to
    # the tail and sort the rest descending.
    sorted_enactments =
      Enum.sort_by(enactments, & &1.inserted_at, fn
        nil, nil -> true
        nil, _b -> false
        _a, nil -> true
        a, b -> DateTime.compare(a, b) != :lt
      end)

    full_entries =
      Enum.map(sorted_enactments, fn e ->
        %FlowEnactmentEntry{
          id: e.id,
          state: e.state,
          inserted_at: datetime_to_iso(e.inserted_at) || ""
        }
      end)

    %{seed: seed, live: live, last_started_at: last_started_at, full_entries: full_entries}
  end

  # Static, marking-free NetDiagram for the per-flow detail page. The detail
  # page renders the structure read-only — no token counts, no glow, no
  # firing pulse — so we emit the cpnet topology with zeroed marking fields.
  defp build_diagram(%ColouredPetriNet{} = cpnet) do
    %NetDiagram{
      places:
        Enum.map(cpnet.places, fn place ->
          %NetDiagramPlace{
            name: place.name,
            colour_set: colour_set_to_string(place.colour_set),
            tokens_count: 0,
            tokens_summary: ""
          }
        end),
      transitions:
        Enum.map(cpnet.transitions, fn transition ->
          %NetDiagramTransition{
            name: transition.name,
            enabled_count: 0,
            rejected_by_guard_count: 0,
            rejected_by_arc_eval_count: 0,
            rejected_by_marking_count: 0,
            last_fired_at: nil
          }
        end),
      arcs:
        Enum.map(cpnet.arcs, fn arc ->
          %NetDiagramArc{
            place: arc.place,
            transition: arc.transition,
            orientation: arc.orientation
          }
        end)
    }
  end

  defp colour_set_to_string(nil), do: ""
  defp colour_set_to_string(name) when is_atom(name), do: Atom.to_string(name)
  defp colour_set_to_string(name) when is_binary(name), do: name
  defp colour_set_to_string(other), do: inspect(other)

  defp compute_counts(rows) do
    %FlowCatalogCounts{
      total_flows: length(rows),
      total_live_enactments: Enum.reduce(rows, 0, &(&1.live_enactments + &2))
    }
  end

  # ---------------------------------------------------------------------------
  # Backend-aware reads
  # ---------------------------------------------------------------------------
  #
  # `Runner.Storage.__storage__/0` is the same backend dispatch
  # `ColouredFlowDashboard.Seed` already uses; both paths are scoped to this
  # store and never mutate runner state. Reads return a uniform shape:
  #
  #   * flow rows: `%{id: binary, name: binary, definition: cpnet}`
  #   * enactment rows: `%{id: binary, flow_id: binary, state: atom,
  #     inserted_at: DateTime.t() | nil}`
  #
  # Public-API audit: the Default backend read is a direct `Repo.all` against
  # `Schemas.Flow` / `Schemas.Enactment` — parallel deviation to the two
  # existing waived Schemas reads. The InMemory backend reads ETS tables
  # owned by the `InMemory` GenServer; the table names are the only
  # non-public surface touched.

  defp list_flow_rows do
    case Storage.__storage__() do
      InMemory -> list_flow_rows_in_memory()
      _default -> list_flow_rows_default()
    end
  rescue
    error ->
      Logger.warning(fn ->
        "FlowCatalogStore: flow listing failed (#{Exception.message(error)}); " <>
          "rendering empty catalog."
      end)

      []
  end

  defp list_flow_rows_in_memory do
    table = in_memory_table(:flow)

    if ets_whereis(table) == :undefined do
      []
    else
      table
      |> :ets.tab2list()
      |> Enum.map(&in_memory_flow_row/1)
      |> Enum.sort_by(& &1.name)
    end
  end

  defp in_memory_flow_row(record) do
    cpnet = InMemory.flow(record, :definition)

    %{
      id: InMemory.flow(record, :id),
      name: seeded_name_for(cpnet),
      definition: cpnet
    }
  end

  defp list_flow_rows_default do
    if repo_configured?() do
      query = from(f in Schemas.Flow, order_by: [asc: f.name])
      Enum.map(Repo.all(query), &%{id: &1.id, name: &1.name, definition: &1.definition})
    else
      Logger.warning(
        "FlowCatalogStore: no Ecto repo configured under " <>
          ":coloured_flow, ColouredFlow.Runner.Storage — catalog will render empty."
      )

      []
    end
  end

  defp list_enactments_by_flow([]), do: %{}

  defp list_enactments_by_flow(flow_ids) when is_list(flow_ids) do
    case Storage.__storage__() do
      InMemory -> list_enactments_in_memory(flow_ids)
      _default -> list_enactments_default(flow_ids)
    end
  rescue
    _error -> %{}
  end

  defp list_enactments_in_memory(flow_ids) do
    table = in_memory_table(:enactment)

    if ets_whereis(table) == :undefined do
      %{}
    else
      table
      |> :ets.tab2list()
      |> Enum.map(&in_memory_enactment_row/1)
      |> Enum.filter(&(&1.flow_id in flow_ids))
      |> Enum.group_by(& &1.flow_id)
    end
  end

  defp in_memory_enactment_row(record) do
    # InMemory holds no lifecycle state column; treat every live row as
    # `:running`. Lifecycle transitions arrive through bridge events and
    # trigger a refresh.
    %{
      id: InMemory.enactment(record, :id),
      flow_id: InMemory.enactment(record, :flow_id),
      state: :running,
      inserted_at: nil
    }
  end

  defp list_enactments_default(flow_ids) do
    if repo_configured?() do
      query =
        from(e in Schemas.Enactment,
          where: e.flow_id in ^flow_ids,
          select: %{
            id: e.id,
            flow_id: e.flow_id,
            state: e.state,
            inserted_at: e.inserted_at
          }
        )

      Enum.group_by(Repo.all(query), & &1.flow_id)
    else
      %{}
    end
  end

  # `Module.safe_concat/2` requires the child atom to already exist. The
  # InMemory child modules (`InMemory.Flow` / `InMemory.Enactment`) are
  # ETS table names created at app boot when the InMemory GenServer
  # initialises, so the atoms are always loaded by the time this store
  # mounts.
  defp in_memory_table(:flow), do: Module.safe_concat(InMemory, "Flow")
  defp in_memory_table(:enactment), do: Module.safe_concat(InMemory, "Enactment")

  defp ets_whereis(name) when is_atom(name), do: :ets.whereis(name)

  # The InMemory backend stores cpnet definitions without a display name —
  # `Schemas.Flow.name` only exists in the Default backend. We recover a
  # human-readable label by matching the cpnet term against the seeded
  # modules' compile-time cpnets; if no seeded module matches, the catalog
  # surfaces a `(unknown)` row that the SPA renders as Start-disabled.
  defp seeded_name_for(%ColouredPetriNet{} = cpnet) do
    Enum.find_value(@seed_by_name, "(unknown)", fn {name, %{module: mod}} ->
      if mod.cpnet() == cpnet, do: name
    end)
  end

  defp repo_configured? do
    case Application.get_env(:coloured_flow, ColouredFlow.Runner.Storage) do
      nil -> false
      cfg when is_list(cfg) -> not is_nil(Keyword.get(cfg, :repo))
      _other -> false
    end
  end

  defp datetime_to_iso(nil), do: nil
  defp datetime_to_iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp datetime_to_iso(%NaiveDateTime{} = ndt),
    do: ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  # ---------------------------------------------------------------------------
  # :start_enactment command
  # ---------------------------------------------------------------------------

  defp start_enactment_reply(nil), do: %{code: :unknown_flow, enactment_id: nil}

  defp start_enactment_reply(flow_id) when is_binary(flow_id) do
    with {:ok, %{name: name} = flow} <- fetch_flow(flow_id),
         {:ok, seed} <- fetch_seed(name),
         {:ok, enactment_id} <- insert_and_start(flow, seed) do
      %{code: :ok, enactment_id: enactment_id}
    else
      {:error, :unknown_flow} ->
        %{code: :unknown_flow, enactment_id: nil}

      {:error, :no_initial_markings} ->
        %{code: :no_initial_markings, enactment_id: nil}

      {:error, {:storage, message}} ->
        %{code: :storage_error, enactment_id: nil, message: message}

      {:error, {:runner, message}} ->
        %{code: :runner_error, enactment_id: nil, message: message}
    end
  end

  defp start_enactment_reply(_other), do: %{code: :unknown_flow, enactment_id: nil}

  defp fetch_flow(flow_id) do
    case Storage.__storage__() do
      InMemory -> fetch_flow_in_memory(flow_id)
      _default -> fetch_flow_default(flow_id)
    end
  rescue
    _error -> {:error, :unknown_flow}
  end

  defp fetch_flow_in_memory(flow_id) do
    table = in_memory_table(:flow)

    with table when table != :undefined <- ets_whereis(table),
         [record] <- :ets.lookup(in_memory_table(:flow), flow_id) do
      {:ok,
       %{
         id: flow_id,
         name: seeded_name_for(InMemory.flow(record, :definition)),
         in_memory_record: record
       }}
    else
      _other -> {:error, :unknown_flow}
    end
  end

  defp fetch_flow_default(flow_id) do
    case repo_configured?() && Repo.get(Schemas.Flow, flow_id) do
      %Schemas.Flow{} = row -> {:ok, %{id: row.id, name: row.name, schema: row}}
      _other -> {:error, :unknown_flow}
    end
  end

  defp fetch_seed(name) do
    case Map.fetch(@seed_by_name, name) do
      {:ok, seed} -> {:ok, seed}
      :error -> {:error, :no_initial_markings}
    end
  end

  defp insert_and_start(flow, seed) do
    with {:ok, enactment_id} <- insert_enactment(flow, seed.initial_markings),
         {:ok, _pid} <- start_runner(enactment_id) do
      {:ok, enactment_id}
    end
  end

  defp insert_enactment(%{in_memory_record: record}, initial_markings) do
    enactment = InMemory.insert_enactment!(record, initial_markings)
    {:ok, InMemory.enactment(enactment, :id)}
  catch
    kind, reason ->
      {:error, {:storage, Exception.format(kind, reason)}}
  end

  defp insert_enactment(%{id: flow_id}, initial_markings) do
    case Storage.insert_enactment(%{flow_id: flow_id, initial_markings: initial_markings}) do
      {:ok, %Schemas.Enactment{id: id}} -> {:ok, id}
    end
  rescue
    error -> {:error, {:storage, Exception.message(error)}}
  catch
    kind, reason -> {:error, {:storage, Exception.format(kind, reason)}}
  end

  defp start_runner(enactment_id) do
    case Runner.start_enactment(enactment_id) do
      {:ok, pid} when is_pid(pid) -> {:ok, pid}
      {:ok, pid, _info} when is_pid(pid) -> {:ok, pid}
      :ignore -> {:error, {:runner, ":ignore"}}
      {:error, reason} -> {:error, {:runner, inspect(reason)}}
    end
  rescue
    error -> {:error, {:runner, Exception.message(error)}}
  catch
    kind, reason -> {:error, {:runner, Exception.format(kind, reason)}}
  end

  # ---------------------------------------------------------------------------
  # :fetch_flow_detail command
  # ---------------------------------------------------------------------------

  defp fetch_flow_detail_reply(flow_id) when is_binary(flow_id) do
    case fetch_flow_row(flow_id) do
      {:ok, row} ->
        enactments = Map.get(list_enactments_by_flow([flow_id]), flow_id, [])
        %{code: :ok, flow: build_detail(row, enactments)}

      {:error, :unknown_flow} ->
        %{code: :not_found, flow: nil}
    end
  rescue
    _error -> %{code: :not_found, flow: nil}
  end

  defp fetch_flow_detail_reply(_other), do: %{code: :not_found, flow: nil}

  # Returns the `%{id, name, definition}` shape `build_detail/2` expects.
  # Separate from `fetch_flow/1` (used by `:start_enactment`) because that
  # path only needs name + storage handle, not the cpnet.
  defp fetch_flow_row(flow_id) do
    case Storage.__storage__() do
      InMemory -> fetch_flow_row_in_memory(flow_id)
      _default -> fetch_flow_row_default(flow_id)
    end
  rescue
    _error -> {:error, :unknown_flow}
  end

  defp fetch_flow_row_in_memory(flow_id) do
    table = in_memory_table(:flow)

    with table when table != :undefined <- ets_whereis(table),
         [record] <- :ets.lookup(in_memory_table(:flow), flow_id) do
      cpnet = InMemory.flow(record, :definition)
      {:ok, %{id: flow_id, name: seeded_name_for(cpnet), definition: cpnet}}
    else
      _other -> {:error, :unknown_flow}
    end
  end

  defp fetch_flow_row_default(flow_id) do
    case repo_configured?() && Repo.get(Schemas.Flow, flow_id) do
      %Schemas.Flow{} = row ->
        {:ok, %{id: row.id, name: row.name, definition: row.definition}}

      _other ->
        {:error, :unknown_flow}
    end
  end
end
