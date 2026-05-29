defmodule ColouredFlowDashboardWeb.SPAControllerTest do
  use ColouredFlowDashboardWeb.ConnCase, async: true

  describe "SPA shell" do
    test "GET / returns HTML 200", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert response_content_type(conn, :html)
      assert conn.status == 200
    end

    test "GET an arbitrary deep path returns the SPA shell (HTML 200)", %{conn: conn} do
      conn = get(conn, "/enactments/some-id")
      assert response_content_type(conn, :html)
      assert conn.status == 200
    end

    test "GET /foo/bar (unknown route) still hits the SPA shell", %{conn: conn} do
      conn = get(conn, "/foo/bar")
      assert response_content_type(conn, :html)
      assert conn.status == 200
    end
  end

  describe "/api/* fallback" do
    test "GET /api/foo returns JSON 404", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/api/foo")

      assert conn.status == 404
      assert response_content_type(conn, :json)
      assert Jason.decode!(conn.resp_body) == %{"errors" => %{"detail" => "Not Found"}}
    end

    test "POST /api/anything returns JSON 404", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> post("/api/anything", %{})

      assert conn.status == 404
    end
  end
end
