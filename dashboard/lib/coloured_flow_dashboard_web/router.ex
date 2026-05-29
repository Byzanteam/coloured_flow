defmodule ColouredFlowDashboardWeb.Router do
  use ColouredFlowDashboardWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :browser do
    plug :accepts, ["html"]
  end

  scope "/api", ColouredFlowDashboardWeb do
    pipe_through :api

    # Any unmatched /api/* path returns JSON 404 instead of falling through
    # to the SPA shell. `match :*` covers every verb.
    match :*, "/*path", FallbackController, :not_found
  end

  scope "/", ColouredFlowDashboardWeb do
    pipe_through :browser

    # SPA shell — React Router owns client-side routing for every
    # non-API path that `Plug.Static` did not match.
    get "/", SPAController, :index
    get "/*path", SPAController, :index
  end
end
