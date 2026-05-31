defmodule ColouredFlowDashboard.Application do
  @moduledoc """
  OTP application entry point for ColouredFlow Dashboard.

  Boots the Phoenix endpoint, the shared `ColouredFlowDashboard.Repo`, the
  Phoenix.PubSub instance named `:coloured_flow_dashboard_pubsub`, the
  `ColouredFlowDashboard.TaskSupervisor` task pool, the
  `ColouredFlowDashboard.TelemetryBridge` runner-events fan-out, the
  `ColouredFlow.Runner.Supervisor` from the parent `coloured_flow` library
  so enactments come up under our supervision tree, and the one-shot
  `ColouredFlowDashboard.EnactmentResumer` which adopts already-persisted
  `:running` enactment rows back into the live Runner supervisor on boot
  (disabled in tests via the `:resume_enactments` config switch).

  When the runner storage is configured to
  `ColouredFlow.Runner.Storage.InMemory` (used in tests), the in-memory ETS
  store is started ahead of `Runner.Supervisor` so enactments can resolve
  their flows.

  Demo flows are NOT seeded on boot; populate the dev database explicitly via
  `mix ecto.setup` (which runs `priv/repo/seeds.exs`) or
  `mix run priv/repo/seeds.exs`.
  """

  use Application

  @impl Application
  def start(_type, _args) do
    children =
      [
        ColouredFlowDashboardWeb.Telemetry,
        ColouredFlowDashboard.Repo,
        {DNSCluster,
         query: Application.get_env(:coloured_flow_dashboard, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: :coloured_flow_dashboard_pubsub},
        {Task.Supervisor, name: ColouredFlowDashboard.TaskSupervisor},
        ColouredFlowDashboard.TelemetryBridge
      ] ++
        storage_children() ++
        [
          ColouredFlow.Runner.Supervisor,
          Supervisor.child_spec(ColouredFlowDashboard.EnactmentResumer, restart: :temporary),
          ColouredFlowDashboardWeb.Endpoint
        ]

    opts = [strategy: :one_for_one, name: ColouredFlowDashboard.Supervisor]

    Supervisor.start_link(children, opts)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    ColouredFlowDashboardWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp storage_children do
    case Application.get_env(:coloured_flow, ColouredFlow.Runner.Storage)[:storage] do
      ColouredFlow.Runner.Storage.InMemory -> [ColouredFlow.Runner.Storage.InMemory]
      _other -> []
    end
  end
end
