defmodule ColouredFlowDashboardWeb.FallbackController do
  @moduledoc """
  Catch-all for unmatched `/socket/*` plain-HTTP requests — returns a JSON
  404 so the SPA shell only ever leaks back through the browser scope.
  The Phoenix Socket transports are mounted at the endpoint level and run
  before the router; this controller only handles plain HTTP that did not
  match a transport.
  """

  use ColouredFlowDashboardWeb, :controller

  @spec not_found(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> put_view(json: ColouredFlowDashboardWeb.ErrorJSON)
    |> render(:"404")
  end
end
