defmodule ColouredFlowDashboardWeb.UserSocketTest do
  use ExUnit.Case, async: true

  alias ColouredFlowDashboardWeb.Endpoint
  alias ColouredFlowDashboardWeb.UserSocket

  describe "Musubi UserSocket placeholder" do
    test "compiles as a Musubi.Socket adapter with an empty roots list" do
      Code.ensure_loaded!(UserSocket)
      assert function_exported?(UserSocket, :__musubi_roots__, 0)
      assert UserSocket.__musubi_roots__() == []
    end

    test "implements the Musubi.Socket lifecycle behaviour" do
      behaviours =
        :attributes
        |> UserSocket.module_info()
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Musubi.Socket in behaviours
      assert Phoenix.Socket in behaviours
    end

    test "is mounted on the dashboard endpoint at /socket" do
      sockets = Endpoint.__sockets__()

      assert Enum.any?(sockets, fn
               {"/socket", UserSocket, _opts} -> true
               _other -> false
             end),
             "expected UserSocket mounted at /socket on the endpoint, got: #{inspect(sockets)}"
    end
  end
end
