defmodule ColouredFlowDashboard.Seed do
  @moduledoc """
  Boots the demo flows on app start so an operator hitting `/` sees a live
  workitem immediately (and Phase 9's end-to-end story is observable).

  Currently seeds four demo flows:

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

  ## Gating

    * `config :coloured_flow_dashboard, :seed_flows, true` enables. Default
      `false` (set explicitly in `config/prod.exs` for the audit trail and
      omitted in `config/test.exs` so test suites stay quiet). Tests that
      need the seed pass `Seed.run(enabled: true)` directly instead of
      mutating the shared `:seed_flows` runtime config (per repo convention
      on `Application.put_env`).
    * `config :coloured_flow, ColouredFlow.Runner.Storage, repo: ...` must
      be wired before `run/0` is invoked; otherwise the seed short-circuits
      with a `:warning` log so the dashboard still boots.

  ## Idempotency

  Within a single BEAM the seed runs at most once per flow: the resulting
  enactment id is stashed in `:persistent_term` keyed by the flow module.
  A second call observes the term, checks the registry, and skips.

  Across BEAM restarts the term is gone, so `do_seed/1` falls back to
  database lookups against `Schemas.Flow` (by `__cpn__(:name)`) and
  `Schemas.Enactment` (by `flow_id`). If a row exists from a prior boot it
  is reused — no fresh insert — and the runner's `start_enactment/1`
  re-spawns the GenServer (replaying from snapshot/occurrences). This is
  why the live dev DB does not accumulate one extra `Schemas.Flow` /
  `Schemas.Enactment` row per `mix phx.server` boot.

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

  require Logger

  @seeded_flows [ApprovalFlow, IncidentTriageFlow, TrafficLightFlow, PiAgentFlow]

  @doc """
  Insert + start every demo flow. Idempotent.

  ## Options

    * `:enabled` — boolean override. Defaults to
      `Application.get_env(:coloured_flow_dashboard, :seed_flows, false)`.
      Tests pass `enabled: true` directly instead of mutating the shared
      `:seed_flows` runtime config key (which would leak across the suite).
  """
  @spec run(keyword()) :: :ok
  def run(opts \\ []) do
    enabled? =
      Keyword.get_lazy(opts, :enabled, fn ->
        Application.get_env(:coloured_flow_dashboard, :seed_flows, false)
      end)

    if enabled? do
      Enum.each(@seeded_flows, &seed_flow/1)
    end

    :ok
  end

  @doc """
  Returns the persistent_term enactment id for a seeded flow, or `nil` when
  the flow has not been seeded in this BEAM. Used by tests + the inbox to
  link the demo workitem back to its enactment.
  """
  @spec enactment_id(module()) :: String.t() | nil
  def enactment_id(flow_module) do
    :persistent_term.get({__MODULE__, flow_module}, nil)
  end

  defp seed_flow(flow_module) do
    case enactment_id(flow_module) do
      nil ->
        do_seed(flow_module)

      id when is_binary(id) ->
        if running?(id) do
          :ok
        else
          do_seed(flow_module)
        end
    end
  rescue
    # Storage may not be configured (Repo missing in a host that mounted
    # the dashboard without wiring it). Log + swallow so the OTP boot
    # sequence continues — the dashboard's other supervised children
    # still come up.
    error ->
      Logger.warning(fn ->
        "[#{inspect(__MODULE__)}] seed for #{inspect(flow_module)} failed: " <>
          Exception.message(error)
      end)

      :ok
  end

  defp do_seed(flow_module) do
    with {:ok, flow_ref, flow_status} <- insert_flow(flow_module),
         {:ok, enactment_id, enactment_status} <-
           insert_enactment(flow_ref, flow_module.__cpn__(:initial_markings)),
         {:ok, _pid} <- Runner.start_enactment(enactment_id) do
      :persistent_term.put({__MODULE__, flow_module}, enactment_id)

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

  # `GenServer.whereis/1` against the runner's registered via-tuple is the
  # standard OTP lookup; the registry process name is the only public
  # surface required and we avoid aliasing the runner's `@moduledoc false`
  # Registry module.
  defp running?(enactment_id) do
    via =
      {:via, Registry, {ColouredFlow.Runner.Enactment.Registry, {:enactment, enactment_id}}}

    is_pid(GenServer.whereis(via))
  end

  # Returns a backend-specific opaque flow reference plus an `:inserted |
  # :reused` status. `{:in_memory, flow_record}` (`InMemory.insert_enactment!/2`
  # wants the record) or `{:default, uuid_string}` (Default backend keys on
  # the bare id). The dispatch in `insert_enactment/2` peels the variant.
  defp insert_flow(flow_module) do
    cpnet = flow_module.cpnet()

    case Storage.__storage__() do
      InMemory ->
        flow = InMemory.insert_flow!(cpnet)
        {:ok, {:in_memory, flow}, :inserted}

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
    require InMemory
    enactment = InMemory.insert_enactment!(flow_record, initial_markings)
    {:ok, InMemory.enactment(enactment, :id), :inserted}
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
end
