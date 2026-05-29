defmodule ColouredFlowDashboard.Application do
  @moduledoc """
  OTP application entry point for ColouredFlow Dashboard.

  Boots the Phoenix endpoint, the shared `ColouredFlowDashboard.Repo`, the
  Phoenix.PubSub instance named `:coloured_flow_dashboard_pubsub`, and the
  `ColouredFlow.Runner.Supervisor` from the parent `coloured_flow` library so
  enactments come up under our supervision tree.
  """

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      ColouredFlowDashboardWeb.Telemetry,
      ColouredFlowDashboard.Repo,
      {DNSCluster, query: Application.get_env(:coloured_flow_dashboard, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: :coloured_flow_dashboard_pubsub},
      ColouredFlow.Runner.Supervisor,
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
end
