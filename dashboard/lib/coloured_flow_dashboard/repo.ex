defmodule ColouredFlowDashboard.Repo do
  use Ecto.Repo,
    otp_app: :coloured_flow_dashboard,
    adapter: Ecto.Adapters.Postgres
end
