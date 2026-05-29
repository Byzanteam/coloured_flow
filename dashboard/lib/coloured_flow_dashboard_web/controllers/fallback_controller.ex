defmodule ColouredFlowDashboardWeb.FallbackController do
  @moduledoc """
  Catch-all for unmatched `/api/*` routes — returns a JSON 404 so the SPA
  shell only ever leaks back through the browser scope.
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
