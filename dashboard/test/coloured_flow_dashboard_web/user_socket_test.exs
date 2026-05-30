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

    # Regression guard for the P0 WS handshake bug: re-introducing
    # `connect_info: [session: ...]` on the WS/longpoll mount makes Phoenix
    # forward `connect_info[:session] = nil` to Musubi 0.6 on first visit
    # (no cookie yet), which crashes `Musubi.Socket.put_session/2` and 500s
    # the WS upgrade. The endpoint MUST mount the socket without a `session`
    # connect_info key — mirroring arbor/examples/{cart_page,chat_room,poll_app}.
    test "endpoint mounts /socket without a session connect_info key" do
      {_path, UserSocket, opts} =
        Enum.find(Endpoint.__sockets__(), fn
          {"/socket", UserSocket, _opts} -> true
          _other -> false
        end)

      refute session_in_connect_info?(opts[:websocket]),
             "websocket connect_info must not request :session — Musubi 0.6 crashes when Phoenix passes session: nil on cookieless first connects. opts=#{inspect(opts)}"

      refute session_in_connect_info?(opts[:longpoll]),
             "longpoll connect_info must not request :session — same Musubi 0.6 crash applies. opts=#{inspect(opts)}"
    end

    test "connect/3 succeeds for a cookieless first visit (empty connect_info)" do
      phoenix_socket = socket(UserSocket, nil, %{})

      assert {:ok, %Phoenix.Socket{}} = UserSocket.connect(%{}, phoenix_socket, %{})
    end

    test "connect/3 succeeds when connect_info carries peer_data but no :session key" do
      phoenix_socket = socket(UserSocket, nil, %{})
      connect_info = %{peer_data: %{address: {127, 0, 0, 1}, port: 0, ssl_cert: nil}}

      assert {:ok, %Phoenix.Socket{}} = UserSocket.connect(%{}, phoenix_socket, connect_info)
    end
  end

  defp session_in_connect_info?(transport_opts) when is_list(transport_opts) do
    connect_info = Keyword.get(transport_opts, :connect_info, [])
    Keyword.has_key?(connect_info, :session)
  end

  defp session_in_connect_info?(_other), do: false
end
