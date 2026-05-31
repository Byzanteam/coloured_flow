defmodule ColouredFlowDashboardWeb.UserSocketTest do
  use ExUnit.Case, async: true

  import Phoenix.ChannelTest

  alias ColouredFlowDashboardWeb.Endpoint
  alias ColouredFlowDashboardWeb.UserSocket

  @endpoint Endpoint

  describe "Musubi UserSocket" do
    test "compiles as a Musubi.Socket adapter and advertises the dashboard root stores" do
      Code.ensure_loaded!(UserSocket)
      assert function_exported?(UserSocket, :__musubi_roots__, 0)

      roots = UserSocket.__musubi_roots__()

      assert ColouredFlowDashboardWeb.Stores.InboxStore in roots
      assert ColouredFlowDashboardWeb.Stores.EnactmentDetailStore in roots
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

    test "connect/3 survives a cookieless first visit (session: nil in connect_info)" do
      # Phoenix's `Plug.Session.Cookie` emits `connect_info[:session] = nil`
      # for cookieless first visits. Musubi 0.6.0 crashed on this shape; 0.6.1
      # normalizes nil → %{} in `Musubi.Transport.Socket.build_connect_socket/2`.
      phoenix_socket = socket(UserSocket, nil, %{})

      assert {:ok, %Phoenix.Socket{}} =
               UserSocket.connect(%{}, phoenix_socket, %{session: nil})
    end

    test "connect/3 succeeds for an empty connect_info" do
      phoenix_socket = socket(UserSocket, nil, %{})

      assert {:ok, %Phoenix.Socket{}} = UserSocket.connect(%{}, phoenix_socket, %{})
    end
  end
end
