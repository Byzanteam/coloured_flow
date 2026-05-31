defmodule ColouredFlowDashboardWeb.SPAController do
  @moduledoc """
  Serves the React SPA shell built by `dashboard/ui/`.

  Vite emits `priv/static/index.html` plus hashed bundles under
  `priv/static/assets/`. `Plug.Static` (mounted in the endpoint) handles the
  hashed assets directly; this controller catches every non-API GET that
  static didn't match and returns the SPA shell so React Router can resolve
  the URL on the client.
  """

  use ColouredFlowDashboardWeb, :controller

  @index_path Application.app_dir(:coloured_flow_dashboard, "priv/static/index.html")

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    case File.read(@index_path) do
      {:ok, body} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, body)

      {:error, :enoent} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, missing_build_html())
    end
  end

  defp missing_build_html do
    """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><title>ColouredFlow Dashboard</title></head>
    <body style="font-family: system-ui; padding: 24px;">
    <h1>SPA bundle not built</h1>
    <p>Run <code>cd dashboard/ui &amp;&amp; pnpm install &amp;&amp; pnpm build</code> to emit
    <code>priv/static/index.html</code>, or start <code>pnpm dev</code> on port 4103
    and open the Vite URL directly.</p>
    </body></html>
    """
  end
end
