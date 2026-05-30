defmodule ColouredFlowDashboard.EnactmentResumer do
  @moduledoc """
  One-shot worker that adopts already-running enactment rows back into the
  live `ColouredFlow.Runner.Enactment.Supervisor` after a phx boot.

  Distinct from `ColouredFlowDashboard.Seed`:

    * `Seed` creates rows (flows + initial enactments) and bootstraps the
      dev database from scratch. It is invoked explicitly via
      `mix ecto.setup` / `mix run priv/repo/seeds.exs`, never from the
      supervision tree.
    * `EnactmentResumer` only adopts existing storage rows whose state is
      `:running` (Default backend) or whose record is present in the ETS
      table (InMemory backend). It runs unconditionally on every phx boot
      so the Runner supervisor reaches steady state without an operator
      having to manually visit each enactment detail page.

  ## Lifecycle

  `init/1` either:

    * returns `:ignore` when `:resume_enactments` is set to `false` (test
      env); the supervisor records this and the resumer is never started
      again, OR
    * schedules a `:resume` message via `Process.send_after(self(), :resume, 0)`
      so the rest of the application supervisor's children finish booting
      before the resume sweep walks storage.

  After one sweep the GenServer terminates with `{:stop, :normal, state}`;
  the wired-up child spec uses `restart: :temporary` so the supervisor
  does not respawn it.

  ## Backend dispatch

  Reads mirror the existing waived deviation in `FlowCatalogStore` /
  `Seed`: `Runner.Storage.__storage__/0` selects between the InMemory
  ETS table and a `Repo.all` against `Schemas.Enactment` on the Default
  (Postgres) backend.
  """

  use GenServer

  alias ColouredFlow.Runner
  alias ColouredFlow.Runner.Storage
  alias ColouredFlow.Runner.Storage.InMemory
  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlowDashboard.Repo

  import Ecto.Query, only: [from: 2]

  require InMemory
  require Logger

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do
    enabled? =
      Keyword.get(
        opts,
        :enabled,
        Application.get_env(:coloured_flow_dashboard, :resume_enactments, true)
      )

    if enabled? do
      Process.send_after(self(), :resume, 0)
      {:ok, %{}}
    else
      :ignore
    end
  end

  @impl GenServer
  def handle_info(:resume, state) do
    resume_all()
    {:stop, :normal, state}
  end

  defp resume_all do
    ids = list_running_enactment_ids()

    {resumed, reused, failed} =
      Enum.reduce(ids, {0, 0, 0}, fn id, {r, u, f} ->
        case adopt(id) do
          :resumed -> {r + 1, u, f}
          :reused -> {r, u + 1, f}
          :failed -> {r, u, f + 1}
        end
      end)

    Logger.info(
      "[EnactmentResumer] resumed #{resumed} enactments " <>
        "(#{reused} reused, #{failed} failed)"
    )
  end

  defp adopt(enactment_id) do
    via =
      {:via, Registry, {ColouredFlow.Runner.Enactment.Registry, {:enactment, enactment_id}}}

    if is_pid(GenServer.whereis(via)) do
      :reused
    else
      case Runner.start_enactment(enactment_id) do
        {:ok, _pid} ->
          :resumed

        other ->
          Logger.warning(
            "[EnactmentResumer] failed to start enactment #{enactment_id}: #{inspect(other)}"
          )

          :failed
      end
    end
  end

  defp list_running_enactment_ids do
    case Storage.__storage__() do
      InMemory -> list_in_memory()
      _default -> list_default()
    end
  rescue
    error ->
      Logger.warning(
        "[EnactmentResumer] failed to list running enactments: " <> Exception.message(error)
      )

      []
  end

  # The InMemory backend has no `state` column on its enactment record —
  # every row in the ETS table is implicitly live. The table is reset on
  # every BEAM boot, so the resumer typically finds nothing here unless a
  # test seeded rows in the same VM.
  defp list_in_memory do
    table = Module.safe_concat(InMemory, "Enactment")

    case :ets.whereis(table) do
      :undefined -> []
      _ref -> for record <- :ets.tab2list(table), do: InMemory.enactment(record, :id)
    end
  end

  defp list_default do
    if repo_configured?() do
      query = from(e in Schemas.Enactment, where: e.state == ^:running, select: e.id)
      Repo.all(query)
    else
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
end
