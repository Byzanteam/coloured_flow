defmodule ColouredFlowDashboardWeb.Stores.EnactmentListStore do
  @moduledoc """
  Root Musubi store backing the enactment list page at `/enactments`.

  Lists every enactment in storage as `EnactmentRow` wire entries so an
  operator can see the global catalog of enactments — running, exception,
  terminated — without first navigating through a workitem row or pasting
  a UUID.

  ## Mount params

  All optional; defaults match the production wiring.

    * `"pubsub_name"` — `Phoenix.PubSub` server name. Defaults to
      `:coloured_flow_dashboard_pubsub`.
    * `"topic"` — topic to subscribe to. Defaults to `"cf:enactments"`.

  ## PubSub topic

  Subscribes to `"cf:enactments"`. The bridge republishes enactment
  lifecycle events (`:enactment_start`, `:enactment_terminate`,
  `:enactment_exception`) to this topic so the list can refresh row state
  without polling storage. Per-enactment monotonic seq sequencing follows
  the same drop-stale pattern as `InboxStore` / `FlowCatalogStore`.

  ## Cross-backend listing

  Backend dispatch via `Runner.Storage.__storage__/0` — same path used by
  `Seed`, `FlowCatalogStore`, and `EnactmentResumer`. The Default
  (Postgres / Ecto) backend reads `Schemas.Enactment` joined with
  `Schemas.Flow.name`; live workitem counts come from a grouped
  `Schemas.Workitem` query. The InMemory backend reads the `:enactment`
  and `:workitem` ETS tables owned by the `InMemory` GenServer; flow
  names are recovered via the seeded-module match
  `FlowCatalogStore.seeded_name_for/1` parallel.

  These reads are parallel deviations to the existing waived
  `Schemas.*` reads in `InboxStore` and `FlowCatalogStore`: there is no
  public `Runner.list_enactments/0`. The next epic upstreams it.

  ## State refresh

  Lifecycle events flip an existing row's `state` in-place and refresh
  the `flow_name` lookup if it was unresolved at mount. `live_workitems`
  is treated as eventually consistent: refreshed on every lifecycle event
  for the row's enactment.
  """

  use Musubi.Store, root: true

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Runner.Enactment.Workitem, as: RunnerWorkitem
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
  alias ColouredFlowDashboardWeb.Views.EnactmentRow

  require InMemory

  import Ecto.Query, only: [from: 2]

  require Logger

  @default_pubsub :coloured_flow_dashboard_pubsub
  @default_topic "cf:enactments"
  @stream_limit 5_000
  @live_states RunnerWorkitem.__live_states__()
  @seeded_modules [ApprovalFlow, IncidentTriageFlow, TrafficLightFlow, PiAgentFlow]

  @seed_by_cpnet for mod <- @seeded_modules,
                     into: %{},
                     do: {mod.cpnet(), mod.__cpn__(:name)}

  # Musubi's `state do` type walker resolves `Mod.t()` against the host
  # module's namespace ancestry. Inline FQN refs.
  state do
    stream :enactments, ColouredFlowDashboardWeb.Views.EnactmentRow.t(),
      limit: @stream_limit,
      item_key: & &1.id

    field :total_enactments, integer()
    field :running_count, integer()
    field :exception_count, integer()
    field :terminated_count, integer()
  end

  @impl Musubi.Store
  def mount(params, socket) when is_map(params) do
    pubsub = Map.get(params, "pubsub_name", @default_pubsub)
    topic = Map.get(params, "topic", @default_topic)

    :ok = Phoenix.PubSub.subscribe(pubsub, topic)

    rows = load_rows()
    counts = compute_counts(rows)
    row_index = Map.new(rows, fn %EnactmentRow{id: id} = row -> {id, row} end)
    flow_names = Map.new(rows, fn %EnactmentRow{flow_id: fid, flow_name: name} -> {fid, name} end)

    socket =
      socket
      |> assign(:pubsub_name, pubsub)
      |> assign(:topic, topic)
      |> assign(:row_index, row_index)
      |> assign(:flow_names, flow_names)
      |> assign(:last_seq, %{})
      |> assign_counts(counts)
      |> stream(:enactments, rows, reset: true)

    {:ok, socket}
  end

  @impl Musubi.Store
  def render(socket) do
    %{
      enactments: stream(:enactments),
      total_enactments: socket.assigns.total_enactments,
      running_count: socket.assigns.running_count,
      exception_count: socket.assigns.exception_count,
      terminated_count: socket.assigns.terminated_count
    }
  end

  @impl Musubi.Store
  def handle_command(_name, _payload, socket), do: {:noreply, socket}

  @impl Musubi.Store
  def handle_info({:cf_event, %Event{} = event}, socket) do
    cond do
      not list_event?(event) ->
        {:noreply, socket}

      SeqTracker.stale?(event, socket.assigns.last_seq) ->
        {:noreply, socket}

      true ->
        socket = assign(socket, :last_seq, SeqTracker.bump(socket.assigns.last_seq, event))
        {:noreply, apply_event(event, socket)}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp list_event?(%Event{kind: kind})
       when kind in [:enactment_start, :enactment_terminate, :enactment_exception],
       do: true

  defp list_event?(%Event{}), do: false

  # ---------------------------------------------------------------------------
  # Event application
  # ---------------------------------------------------------------------------

  defp apply_event(%Event{enactment_id: eid, kind: kind} = event, socket) do
    new_state = state_for_kind(kind)
    iso = datetime_to_iso(event.occurred_at) || ""

    case Map.fetch(socket.assigns.row_index, eid) do
      {:ok, %EnactmentRow{} = row} ->
        updated = %EnactmentRow{
          row
          | state: new_state,
            updated_at: iso,
            live_workitems: live_workitems_for(eid)
        }

        upsert_row(socket, updated)

      :error ->
        # Row absent — either a fresh `:enactment_start` for an enactment
        # the mount seed did not see, or a backend that races the bridge
        # ahead of the storage row. Reload that row directly so the list
        # picks up the new entry without a full refresh.
        case load_row(eid) do
          {:ok, %EnactmentRow{} = row} ->
            row = %EnactmentRow{row | state: new_state, updated_at: iso}
            upsert_row(socket, row)

          :error ->
            socket
        end
    end
  end

  defp state_for_kind(:enactment_start), do: :running
  defp state_for_kind(:enactment_terminate), do: :terminated
  defp state_for_kind(:enactment_exception), do: :exception

  defp upsert_row(socket, %EnactmentRow{id: id} = row) do
    row_index = Map.put(socket.assigns.row_index, id, row)
    counts = compute_counts(Map.values(row_index))

    socket
    |> stream_insert(:enactments, row)
    |> assign(:row_index, row_index)
    |> assign_counts(counts)
  end

  defp assign_counts(socket, %{
         total: total,
         running: running,
         exception: exception,
         terminated: terminated
       }) do
    socket
    |> assign(:total_enactments, total)
    |> assign(:running_count, running)
    |> assign(:exception_count, exception)
    |> assign(:terminated_count, terminated)
  end

  defp compute_counts(rows) do
    by_state = Enum.frequencies_by(rows, & &1.state)

    %{
      total: length(rows),
      running: Map.get(by_state, :running, 0),
      exception: Map.get(by_state, :exception, 0),
      terminated: Map.get(by_state, :terminated, 0)
    }
  end

  # ---------------------------------------------------------------------------
  # Backend-aware reads
  # ---------------------------------------------------------------------------

  defp load_rows do
    case Storage.__storage__() do
      InMemory -> load_rows_in_memory()
      _default -> load_rows_default()
    end
  rescue
    error ->
      Logger.warning(fn ->
        "EnactmentListStore: listing failed (#{Exception.message(error)}); " <>
          "rendering empty list."
      end)

      []
  end

  defp load_rows_in_memory do
    enactment_table = in_memory_table(:enactment)

    if ets_whereis(enactment_table) == :undefined do
      []
    else
      flow_names = in_memory_flow_names()
      workitem_counts = in_memory_workitem_counts()

      enactment_table
      |> :ets.tab2list()
      |> Enum.map(fn record ->
        eid = InMemory.enactment(record, :id)
        fid = InMemory.enactment(record, :flow_id)

        %EnactmentRow{
          id: eid,
          flow_id: fid,
          flow_name: Map.get(flow_names, fid, ""),
          # InMemory holds no lifecycle column — treat every row as :running.
          # Bridge events flip terminated / exception rows in-place.
          state: :running,
          inserted_at: "",
          updated_at: "",
          live_workitems: Map.get(workitem_counts, eid, 0)
        }
      end)
      |> Enum.sort_by(& &1.id)
    end
  end

  defp in_memory_flow_names do
    flow_table = in_memory_table(:flow)

    if ets_whereis(flow_table) == :undefined do
      %{}
    else
      flow_table
      |> :ets.tab2list()
      |> Map.new(fn record ->
        cpnet = InMemory.flow(record, :definition)
        {InMemory.flow(record, :id), seeded_name_for(cpnet)}
      end)
    end
  end

  defp in_memory_workitem_counts do
    workitem_table = in_memory_table(:workitem)

    if ets_whereis(workitem_table) == :undefined do
      %{}
    else
      workitem_table
      |> :ets.tab2list()
      |> Enum.reduce(%{}, &accumulate_live_workitem/2)
    end
  end

  defp accumulate_live_workitem(record, acc) do
    if InMemory.workitem(record, :state) in @live_states do
      eid = InMemory.workitem(record, :enactment_id)
      Map.update(acc, eid, 1, &(&1 + 1))
    else
      acc
    end
  end

  defp load_rows_default do
    if repo_configured?() do
      query =
        from(e in Schemas.Enactment,
          join: f in Schemas.Flow,
          on: f.id == e.flow_id,
          select: %{
            id: e.id,
            flow_id: e.flow_id,
            flow_name: f.name,
            state: e.state,
            inserted_at: e.inserted_at,
            updated_at: e.updated_at
          },
          order_by: [desc: e.inserted_at]
        )

      rows = Repo.all(query)
      workitem_counts = default_workitem_counts(Enum.map(rows, & &1.id))

      Enum.map(rows, fn row ->
        %EnactmentRow{
          id: row.id,
          flow_id: row.flow_id,
          flow_name: row.flow_name || "",
          state: row.state,
          inserted_at: datetime_to_iso(row.inserted_at) || "",
          updated_at: datetime_to_iso(row.updated_at) || "",
          live_workitems: Map.get(workitem_counts, row.id, 0)
        }
      end)
    else
      Logger.warning(
        "EnactmentListStore: no Ecto repo configured under " <>
          ":coloured_flow, ColouredFlow.Runner.Storage — list will render empty."
      )

      []
    end
  end

  defp default_workitem_counts([]), do: %{}

  defp default_workitem_counts(enactment_ids) do
    live_states = @live_states

    query =
      from(w in Schemas.Workitem,
        where: w.enactment_id in ^enactment_ids and w.state in ^live_states,
        group_by: w.enactment_id,
        select: {w.enactment_id, count(w.id)}
      )

    query |> Repo.all() |> Map.new()
  rescue
    _error -> %{}
  end

  # Lazy single-row read used when a bridge event references an enactment
  # the mount seed did not see (e.g. fresh `:enactment_start` after page
  # mount). Returns `:error` when storage cannot resolve the row so the
  # event handler can no-op without surfacing a half-shaped row.
  defp load_row(enactment_id) do
    case Storage.__storage__() do
      InMemory -> load_row_in_memory(enactment_id)
      _default -> load_row_default(enactment_id)
    end
  rescue
    _error -> :error
  end

  defp load_row_in_memory(enactment_id) do
    table = in_memory_table(:enactment)

    with table when table != :undefined <- ets_whereis(table),
         [record] <- :ets.lookup(in_memory_table(:enactment), enactment_id) do
      fid = InMemory.enactment(record, :flow_id)
      flow_names = in_memory_flow_names()

      {:ok,
       %EnactmentRow{
         id: enactment_id,
         flow_id: fid,
         flow_name: Map.get(flow_names, fid, ""),
         state: :running,
         inserted_at: "",
         updated_at: "",
         live_workitems: live_workitems_for(enactment_id)
       }}
    else
      _other -> :error
    end
  end

  defp load_row_default(enactment_id) do
    if repo_configured?() do
      query =
        from(e in Schemas.Enactment,
          join: f in Schemas.Flow,
          on: f.id == e.flow_id,
          where: e.id == ^enactment_id,
          select: %{
            id: e.id,
            flow_id: e.flow_id,
            flow_name: f.name,
            state: e.state,
            inserted_at: e.inserted_at,
            updated_at: e.updated_at
          }
        )

      case Repo.one(query) do
        nil ->
          :error

        row ->
          {:ok,
           %EnactmentRow{
             id: row.id,
             flow_id: row.flow_id,
             flow_name: row.flow_name || "",
             state: row.state,
             inserted_at: datetime_to_iso(row.inserted_at) || "",
             updated_at: datetime_to_iso(row.updated_at) || "",
             live_workitems: live_workitems_for(row.id)
           }}
      end
    else
      :error
    end
  end

  defp live_workitems_for(enactment_id) do
    case Storage.__storage__() do
      InMemory ->
        Map.get(in_memory_workitem_counts(), enactment_id, 0)

      _default ->
        Map.get(default_workitem_counts([enactment_id]), enactment_id, 0)
    end
  rescue
    _error -> 0
  end

  defp in_memory_table(:flow), do: Module.safe_concat(InMemory, "Flow")
  defp in_memory_table(:enactment), do: Module.safe_concat(InMemory, "Enactment")
  defp in_memory_table(:workitem), do: Module.safe_concat(InMemory, "Workitem")

  defp ets_whereis(name) when is_atom(name), do: :ets.whereis(name)

  # InMemory backend stores cpnet definitions without a display name —
  # `Schemas.Flow.name` only exists in the Default backend. Recover a
  # readable label by matching the cpnet term against the seeded modules'
  # compile-time cpnets; if no match, surface "" so the SPA can fall
  # back to the flow id.
  defp seeded_name_for(%ColouredPetriNet{} = cpnet) do
    Map.get(@seed_by_cpnet, cpnet, "")
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
end
