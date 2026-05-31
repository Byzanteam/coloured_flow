defmodule ColouredFlowDashboardWeb.Stores.TelemetryFeedStoreTest do
  use ExUnit.Case, async: false

  alias ColouredFlowDashboard.TelemetryBridge
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboardWeb.Stores.TelemetryFeedStore

  @pubsub :coloured_flow_dashboard_pubsub
  @events_buffer :cf_dashboard_telemetry_feed_store_test_events_buffer

  setup context do
    topic = "cf-test-#{discriminator(context)}:telemetry"
    events_buffer = @events_buffer

    on_exit(fn ->
      if :ets.whereis(events_buffer) != :undefined do
        :ets.delete(events_buffer)
      end
    end)

    {:ok, topic: topic, events_buffer: events_buffer}
  end

  describe "mount/2" do
    test "seeds zeroed window + counters", %{topic: topic, events_buffer: events_buffer} do
      page = mount_store(topic, 10, events_buffer)
      assigns = Musubi.Testing.assigns(page)

      assert assigns.total_events == 0
      assert assigns.entries_in_window == 0
      # Musubi's `assign/3` skips nil-on-empty assigns; read through Map.get
      # so the seed value surfaces correctly.
      assert Map.get(assigns, :oldest_seq) == nil
      assert Map.get(assigns, :newest_seq) == nil
      assert assigns.entries_index == []
    end

    test "backfills the stream from the bridge events buffer", %{
      topic: topic,
      events_buffer: events_buffer
    } do
      eid_a = Ecto.UUID.generate()
      eid_b = Ecto.UUID.generate()

      seed_events_buffer(events_buffer, [
        build_event(:enactment_start, eid_a, 2),
        build_event(:enactment_start, eid_b, 5)
      ])

      page = mount_store(topic, 10, events_buffer)
      assigns = Musubi.Testing.assigns(page)

      assert assigns.total_events == 2
      assert assigns.entries_in_window == 2
      assert assigns.newest_seq == 5
      assert assigns.oldest_seq == 2
      assert Enum.map(assigns.entries_index, &elem(&1, 1)) == [5, 2]
    end

    test "live PubSub events arrive after backfill without duplicating buffer entries", %{
      topic: topic,
      events_buffer: events_buffer
    } do
      eid = Ecto.UUID.generate()
      backfill = build_event(:produce_workitems_stop, eid, 5)
      seed_events_buffer(events_buffer, [backfill])

      page = mount_store(topic, 5, events_buffer)
      broadcast!(topic, backfill)
      broadcast!(topic, build_event(:complete_workitems_stop, eid, 6))

      assigns = Musubi.Testing.assigns(page)

      assert assigns.total_events == 2
      assert assigns.entries_in_window == 2
      assert assigns.newest_seq == 6
      assert assigns.oldest_seq == 5
      assert Enum.map(assigns.entries_index, &elem(&1, 1)) == [6, 5]
    end
  end

  describe "event ingestion" do
    setup %{topic: topic, events_buffer: events_buffer} do
      page = mount_store(topic, 5, events_buffer)
      {:ok, page: page}
    end

    test "appends an entry on cf:telemetry broadcast",
         %{topic: topic, page: page} do
      eid = Ecto.UUID.generate()
      broadcast!(topic, build_event(:produce_workitems_stop, eid, 1))

      assigns = Musubi.Testing.assigns(page)

      assert assigns.total_events == 1
      assert assigns.entries_in_window == 1
      assert assigns.newest_seq == 1
      assert assigns.oldest_seq == 1
    end

    test "trims to window cap when overflowing",
         %{topic: topic, page: page} do
      eid = Ecto.UUID.generate()

      for seq <- 1..7 do
        broadcast!(topic, build_event(:produce_workitems_stop, eid, seq))
      end

      assigns = Musubi.Testing.assigns(page)

      # Window cap is 5; total counter keeps every accepted event.
      assert assigns.total_events == 7
      assert assigns.entries_in_window == 5
      assert assigns.newest_seq == 7
      # Oldest seq in the window is total_events - cap + 1 = 7 - 5 + 1 = 3
      assert assigns.oldest_seq == 3
    end

    test "drops stale events per enactment", %{topic: topic, page: page} do
      eid = Ecto.UUID.generate()

      broadcast!(topic, build_event(:produce_workitems_stop, eid, 5))
      broadcast!(topic, build_event(:start_workitems_stop, eid, 3))
      broadcast!(topic, build_event(:complete_workitems_stop, eid, 4))

      assigns = Musubi.Testing.assigns(page)

      # Only the seq=5 event is accepted; the two trailing events are dropped
      # because they share the enactment id with a higher-seq event.
      assert assigns.total_events == 1
      assert assigns.entries_in_window == 1
      assert assigns.newest_seq == 5
    end

    test "bounds last_seq under distinct-enactment churn", %{topic: topic, page: page} do
      for seq <- 1..1_200 do
        broadcast!(topic, build_event(:produce_workitems_stop, Ecto.UUID.generate(), seq))
      end

      assigns = Musubi.Testing.assigns(page)

      assert assigns.entries_in_window == 5
      assert map_size(assigns.last_seq) <= 5
    end

    test "two enactments interleave without stale-drop crosstalk",
         %{topic: topic, page: page} do
      eid_a = Ecto.UUID.generate()
      eid_b = Ecto.UUID.generate()

      broadcast!(topic, build_event(:produce_workitems_stop, eid_a, 10))
      broadcast!(topic, build_event(:produce_workitems_stop, eid_b, 3))

      assigns = Musubi.Testing.assigns(page)

      assert assigns.total_events == 2
      assert assigns.entries_in_window == 2
      # Endpoints follow bridge seq, not arrival order — newest is the
      # max seq in the window, oldest the min. The store sorts by seq so
      # cross-enactment events stay correctly ordered even when the
      # bridge's per-event Task fan-out lets B's seq=3 land after A's
      # seq=10.
      assert assigns.newest_seq == 10
      assert assigns.oldest_seq == 3
    end

    test "out-of-order arrivals sort into the stream by seq",
         %{topic: topic, page: page} do
      eid_a = Ecto.UUID.generate()
      eid_b = Ecto.UUID.generate()

      # A's seq=10 arrives BEFORE B's seq=5 (older event lands later — the
      # Task fan-out race that motivated the position-based insert).
      broadcast!(topic, build_event(:produce_workitems_stop, eid_a, 10))
      broadcast!(topic, build_event(:produce_workitems_stop, eid_b, 5))

      assigns = Musubi.Testing.assigns(page)
      [{_id, head_seq} | _rest] = assigns.entries_index
      tail_seq = assigns.entries_index |> List.last() |> elem(1)

      assert head_seq == 10
      assert tail_seq == 5
      assert assigns.newest_seq == 10
      assert assigns.oldest_seq == 5
    end

    test "render/1 surfaces total + window + seq endpoints",
         %{topic: topic, page: page} do
      eid = Ecto.UUID.generate()
      broadcast!(topic, build_event(:enactment_start, eid, 42))

      rendered = Musubi.Testing.render(page)

      assert rendered.total_events == 1
      assert rendered.entries_in_window == 1
      assert rendered.newest_seq == 42
      assert rendered.oldest_seq == 42
      assert %Musubi.Stream.Placeholder{name: :entries} = rendered.entries
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp discriminator(context),
    do: Integer.to_string(:erlang.phash2({context.module, context.test}))

  defp mount_store(topic, window, events_buffer) do
    Musubi.Testing.mount(TelemetryFeedStore, %{
      "topic" => topic,
      "window" => window,
      "events_buffer" => events_buffer
    })
  end

  defp seed_events_buffer(events_buffer, events) do
    :ets.new(events_buffer, [:set, :public, :named_table])

    Enum.each(events, fn %Event{} = event ->
      :ets.insert(events_buffer, {event.seq, event})
    end)

    assert TelemetryBridge.recent_events(events_buffer) == Enum.sort_by(events, & &1.seq)
  end

  defp broadcast!(topic, %Event{} = event) do
    :ok = Phoenix.PubSub.broadcast(@pubsub, topic, {:cf_event, event})
  end

  defp build_event(kind, enactment_id, seq) do
    %Event{
      topic: :telemetry,
      kind: kind,
      enactment_id: enactment_id,
      enactment_version: seq,
      seq: seq,
      occurred_at: DateTime.utc_now(),
      payload: %{workitems: []}
    }
  end
end
