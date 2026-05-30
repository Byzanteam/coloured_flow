defmodule Mix.Tasks.Cf.Dashboard.ResetSeedDb do
  @moduledoc """
  Truncate the dashboard dev seed tables so the next `mix phx.server` boot
  re-creates exactly the four demo flow rows + four enactment rows from
  `ColouredFlowDashboard.Seed`.

  Refuses to run outside `MIX_ENV=dev` — production / test databases must
  never see this. Targets the `coloured_flow` schema in the
  `coloured_flow_dashboard_dev` database (configured on
  `ColouredFlowDashboard.Repo`).

      $ MIX_ENV=dev mix cf.dashboard.reset_seed_db
  """
  use Mix.Task

  alias ColouredFlowDashboard.Repo

  @shortdoc "Truncate the dashboard dev seed tables (MIX_ENV=dev only)"

  # All tables sit under the `coloured_flow` schema (see
  # `ColouredFlow.Runner.Storage.Schemas.Schema` / migrations V0..V3).
  # Ordered children-before-parents even though `TRUNCATE ... CASCADE`
  # tolerates either, so reviewers see the intent.
  @tables ~w[enactment_logs occurrences workitems snapshots enactments flows]

  @impl Mix.Task
  # `Mix.env/0` here gates a destructive DDL operation behind the dev
  # compilation env; this is a Mix task, where `Mix.env` is the canonical
  # source of truth (no runtime config equivalent applies).
  # credo:disable-for-next-line Credo.Check.Warning.MixEnv
  def run(_args), do: reset!(Mix.env())

  @doc false
  @spec reset!(atom()) :: :ok
  def reset!(:dev) do
    Mix.Task.run("app.start")

    qualified = Enum.map_join(@tables, ", ", &"coloured_flow.#{&1}")
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE #{qualified} CASCADE", [])

    Mix.shell().info("Truncated coloured_flow.{#{Enum.join(@tables, ",")}}.")
    :ok
  end

  def reset!(env) do
    Mix.raise("cf.dashboard.reset_seed_db refuses to run in MIX_ENV=#{env}; only :dev is allowed")
  end
end
