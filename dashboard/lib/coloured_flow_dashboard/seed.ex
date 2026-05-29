defmodule ColouredFlowDashboard.Seed do
  @moduledoc """
  Boots the demo flows on app start so an operator hitting `/` sees a live
  workitem immediately (and Phase 9's end-to-end story is observable).

  Currently seeds `ColouredFlowDashboard.Seeds.ApprovalFlow`. Future demo
  flows (`traffic_light`, `pi_agent`) plug in alongside.

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
  A second call observes the term, checks the registry, and skips. After a
  BEAM restart the term is gone; the Default (Postgres) backend then sees
  the historical enactment row but a fresh `start_enactment/1` call
  re-spawns the GenServer (the runner replays from snapshot/occurrences).

  ## Cross-backend support

  | Backend     | flow insert                            | enactment insert                   |
  | ----------- | -------------------------------------- | ---------------------------------- |
  | `Default`   | `Repo.insert!(%Schemas.Flow{...})`     | `Storage.insert_enactment/1`       |
  | `InMemory`  | `Storage.InMemory.insert_flow!/1`      | `Storage.InMemory.insert_enactment!/2` |

  The Default backend's `insert_enactment/1` returns a `Schemas.Enactment`;
  the InMemory record is an Erlang record. Both expose `:id` (UUID) via the
  `enactment_id/1` extractor.
  """

  alias ColouredFlow.Runner.Enactment.Registry
  alias ColouredFlow.Runner.Enactment.Supervisor, as: EnactmentSupervisor
  alias ColouredFlow.Runner.Storage
  alias ColouredFlow.Runner.Storage.InMemory
  alias ColouredFlowDashboard.Seeds.ApprovalFlow

  require Logger

  @seeded_flows [ApprovalFlow]

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
    with {:ok, flow_ref} <- insert_flow(flow_module.cpnet()),
         {:ok, enactment_id} <-
           insert_enactment(flow_ref, flow_module.__cpn__(:initial_markings)),
         {:ok, _pid} <- EnactmentSupervisor.start_enactment(enactment_id) do
      :persistent_term.put({__MODULE__, flow_module}, enactment_id)
      Logger.info("[#{inspect(__MODULE__)}] seeded #{inspect(flow_module)} → #{enactment_id}")
      :ok
    end
  end

  defp running?(enactment_id) do
    case Elixir.Registry.lookup(Registry, {:enactment, enactment_id}) do
      [] -> false
      [{_pid, _value} | _rest] -> true
    end
  end

  # Returns a backend-specific opaque flow reference:
  # `{:in_memory, flow_record}` (`InMemory.insert_enactment!/2` wants the
  # record) or `{:default, uuid_string}` (Default backend keys on the bare
  # id). The dispatch in `insert_enactment/2` peels the variant.
  defp insert_flow(cpnet) do
    case Storage.__storage__() do
      InMemory ->
        flow = InMemory.insert_flow!(cpnet)
        {:ok, {:in_memory, flow}}

      _default ->
        alias ColouredFlow.Runner.Storage.Schemas

        flow =
          ColouredFlowDashboard.Repo.insert!(%Schemas.Flow{
            name: "Approval Demo",
            definition: cpnet
          })

        {:ok, {:default, flow.id}}
    end
  end

  defp insert_enactment({:in_memory, flow_record}, initial_markings) do
    require InMemory
    enactment = InMemory.insert_enactment!(flow_record, initial_markings)
    {:ok, InMemory.enactment(enactment, :id)}
  end

  defp insert_enactment({:default, flow_id}, initial_markings) do
    {:ok, enactment} =
      Storage.insert_enactment(%{flow_id: flow_id, initial_markings: initial_markings})

    {:ok, enactment.id}
  end
end
