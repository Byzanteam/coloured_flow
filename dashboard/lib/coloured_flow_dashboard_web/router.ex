defmodule ColouredFlowDashboardWeb.Router do
  use ColouredFlowDashboardWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ColouredFlowDashboardWeb do
    pipe_through :api
  end
end
