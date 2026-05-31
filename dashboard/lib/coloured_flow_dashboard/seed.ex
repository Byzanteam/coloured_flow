defmodule ColouredFlowDashboard.Seed do
  @moduledoc """
  Inserts and starts the demo flows used by the dashboard's operator /
  drawer / replay stories.

  Seeds four flows:

    * `ColouredFlowDashboard.Seeds.ApprovalFlow` — drives the binary-output
      drawer demo.
    * `ColouredFlowDashboard.Seeds.IncidentTriageFlow` — drives the M5
      enum + boolean + string structured form.
    * `ColouredFlowDashboard.Seeds.TrafficLightFlow` — eight-place / six-
      transition choreography from the canonical CPN example. Exercises
      the React Flow layout + replay timeline on a non-trivial diagram.
    * `ColouredFlowDashboard.Seeds.PiAgentFlow` — multi-token list-valued
      markings + atom-union colour sets, adapted from the
      `examples/pi_agent.livemd` ReAct net.

  ## Invocation

  Seeding is intentionally NOT wired into `Application.start/2` — booting
  the OTP app must not side-effect the shared dev DB. Operators populate
  the dev DB explicitly via the Ecto convention:

      mix ecto.setup                  # create + migrate + run seeds
      mix run priv/repo/seeds.exs     # re-run seeds against an existing DB

  `priv/repo/seeds.exs` is a thin wrapper that calls `run/1`.

  ## Idempotency (DB is the source of truth)

  Both `insert_flow/1` and `insert_enactment/2` look up existing rows by
  `Schemas.Flow.name` / `Schemas.Enactment.flow_id` before inserting. A
  second invocation of `run/1` against the same database reuses the rows
  and re-spawns the runner GenServers — no duplicate rows accumulate per
  invocation.

  ## Public-API deviation

  Querying `Schemas.Flow` + `Schemas.Enactment` directly via the dashboard
  `Repo` is a knowing deviation from the "main-repo public surface only"
  rule, in the same class as `InboxStore.query_enactment_states`,
  `EnactmentDetailStore.authoritative_enactment_state`, and
  `FlowCatalogStore.list_flow_rows_default`. The seed already had to insert
  rows on these schemas; reading them back to dedupe is the same exposure.

  ## Cross-backend support

  | Backend     | flow insert                            | enactment insert                       |
  | ----------- | -------------------------------------- | -------------------------------------- |
  | `Default`   | `Repo.insert!(%Schemas.Flow{...})`     | `Storage.insert_enactment/1`           |
  | `InMemory`  | `Storage.InMemory.insert_flow!/1`      | `Storage.InMemory.insert_enactment!/2` |

  The Default backend's `insert_enactment/1` returns a `Schemas.Enactment`;
  the InMemory record is an Erlang record. Both expose `:id` (UUID) via the
  `enactment_id/1` extractor. The InMemory backend is process-scoped and
  rebuilt on every boot, so the dedupe lookups only run on the Default
  (Postgres) backend.
  """

  import Ecto.Query, only: [from: 2]

  alias ColouredFlow.Runner
  alias ColouredFlow.Runner.Storage
  alias ColouredFlow.Runner.Storage.InMemory
  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlowDashboard.Repo
  alias ColouredFlowDashboard.Seeds.ApprovalFlow
  alias ColouredFlowDashboard.Seeds.IncidentTriageFlow
  alias ColouredFlowDashboard.Seeds.PiAgentFlow
  alias ColouredFlowDashboard.Seeds.TrafficLightFlow

  require InMemory
  require Logger

  @seeded_flows [ApprovalFlow, IncidentTriageFlow, TrafficLightFlow, PiAgentFlow]

  @doc """
  Insert + start every demo flow. Idempotent against the Default (Postgres)
  backend — second invocation reuses rows.

  Options are accepted for backward compatibility with existing test
  callers (`Seed.run(enabled: true)`); they are ignored. The function
  always seeds when called.
  """
  @spec run(keyword()) :: :ok
  def run(_opts \\ []) do
    Enum.each(@seeded_flows, &seed_flow/1)
    :ok
  end

  @doc """
  Returns the enactment id that the seeded `flow_module` was registered
  under, or `nil` if it has not been seeded against the current storage
  backend.

  Resolves via DB lookup — no in-process cache. On the Default backend it
  joins `Schemas.Enactment ↔ Schemas.Flow` by `__cpn__(:name)`. On the
  InMemory backend it walks the ETS `flow` table comparing the cached
  `ColouredPetriNet` definition and then resolves the first matching
  enactment.
  """
  @spec enactment_id(module()) :: String.t() | nil
  def enactment_id(flow_module) do
    case Storage.__storage__() do
      InMemory -> in_memory_enactment_id(flow_module)
      _default -> default_enactment_id(flow_module)
    end
  end

  defp seed_flow(flow_module) do
    with {:ok, flow_ref, flow_status} <- insert_flow(flow_module),
         {:ok, enactment_id, enactment_status} <-
           insert_enactment(flow_ref, flow_module.__cpn__(:initial_markings)),
         {:ok, _pid} <- Runner.start_enactment(enactment_id) do
      verb =
        if flow_status == :reused and enactment_status == :reused do
          "reused"
        else
          "seeded"
        end

      Logger.info("[#{inspect(__MODULE__)}] #{verb} #{inspect(flow_module)} → #{enactment_id}")
      :ok
    end
  end

  # Returns a backend-specific opaque flow reference plus an `:inserted |
  # :reused` status. `{:in_memory, flow_record}` (`InMemory.insert_enactment!/2`
  # wants the record) or `{:default, uuid_string}` (Default backend keys on
  # the bare id). The dispatch in `insert_enactment/2` peels the variant.
  defp insert_flow(flow_module) do
    cpnet = flow_module.cpnet()

    case Storage.__storage__() do
      InMemory ->
        case find_in_memory_flow(cpnet) do
          {:ok, existing} ->
            {:ok, {:in_memory, existing}, :reused}

          :error ->
            {:ok, {:in_memory, InMemory.insert_flow!(cpnet)}, :inserted}
        end

      _default ->
        name = flow_module.__cpn__(:name)
        query = from f in Schemas.Flow, where: f.name == ^name, limit: 1

        case Repo.one(query) do
          nil ->
            flow = Repo.insert!(%Schemas.Flow{name: name, definition: cpnet})
            {:ok, {:default, flow.id}, :inserted}

          %Schemas.Flow{} = existing ->
            {:ok, {:default, existing.id}, :reused}
        end
    end
  end

  defp insert_enactment({:in_memory, flow_record}, initial_markings) do
    flow_id = InMemory.flow(flow_record, :id)

    case find_in_memory_enactment_by_flow(flow_id) do
      {:ok, existing} ->
        {:ok, InMemory.enactment(existing, :id), :reused}

      :error ->
        enactment = InMemory.insert_enactment!(flow_record, initial_markings)
        {:ok, InMemory.enactment(enactment, :id), :inserted}
    end
  end

  defp insert_enactment({:default, flow_id}, initial_markings) do
    query = from e in Schemas.Enactment, where: e.flow_id == ^flow_id, limit: 1

    case Repo.one(query) do
      nil ->
        {:ok, enactment} =
          Storage.insert_enactment(%{flow_id: flow_id, initial_markings: initial_markings})

        {:ok, enactment.id, :inserted}

      %Schemas.Enactment{} = existing ->
        {:ok, existing.id, :reused}
    end
  end

  defp default_enactment_id(flow_module) do
    name = flow_module.__cpn__(:name)

    query =
      from e in Schemas.Enactment,
        join: f in Schemas.Flow,
        on: e.flow_id == f.id,
        where: f.name == ^name,
        select: e.id,
        limit: 1

    Repo.one(query)
  end

  defp in_memory_enactment_id(flow_module) do
    cpnet = flow_module.cpnet()

    with {:ok, flow_record} <- find_in_memory_flow(cpnet),
         flow_id = InMemory.flow(flow_record, :id),
         {:ok, enactment_record} <- find_in_memory_enactment_by_flow(flow_id) do
      InMemory.enactment(enactment_record, :id)
    else
      :error -> nil
    end
  end

  defp find_in_memory_flow(cpnet) do
    find_in_table(Module.safe_concat(InMemory, "Flow"), fn record ->
      InMemory.flow(record, :definition) == cpnet
    end)
  end

  defp find_in_memory_enactment_by_flow(flow_id) do
    find_in_table(Module.safe_concat(InMemory, "Enactment"), fn record ->
      InMemory.enactment(record, :flow_id) == flow_id
    end)
  end

  # `:ets.tab2list/1` raises `ArgumentError` when the named table does not
  # exist yet (InMemory GenServer not started). Treat as "no seed".
  defp find_in_table(table, predicate) do
    case table |> :ets.tab2list() |> Enum.find(predicate) do
      nil -> :error
      record -> {:ok, record}
    end
  rescue
    ArgumentError -> :error
  end
end
