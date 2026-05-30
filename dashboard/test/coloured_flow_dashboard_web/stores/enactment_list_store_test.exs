defmodule ColouredFlowDashboardWeb.Stores.EnactmentListStoreTest do
  # `async: false` parallels `InboxStoreTest` and `FlowCatalogStoreTest`: the
  # store's mount/2 reads either Repo or InMemory tables from the spawned
  # Musubi page server (cross-process sandbox concerns) and shares the
  # app-singleton InMemory ETS tables with the rest of the suite.
  use ColouredFlowDashboard.DataCase, async: false

  alias ColouredFlow.Runner.Storage.InMemory
  alias ColouredFlowDashboard.Seeds.ApprovalFlow
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboardWeb.Stores.EnactmentListStore
  alias ColouredFlowDashboardWeb.Views.EnactmentRow

  require InMemory

  @pubsub :coloured_flow_dashboard_pubsub

  setup context do
    topic = "cf-test-#{discriminator(context)}:enactments"
    {:ok, topic: topic}
  end

  describe "mount/2" do
    test "renders an empty stream placeholder for :enactments", %{topic: topic} do
      page = mount_store(topic)

      assert %{enactments: %Musubi.Stream.Placeholder{name: :enactments}} =
               Musubi.Testing.render(page)
    end

    test "seeds row index from an enactment inserted via the InMemory backend",
         %{topic: topic} do
      flow_record = InMemory.insert_flow!(ApprovalFlow.cpnet())
      flow_id = InMemory.flow(flow_record, :id)

      {:ok, enactment} =
        ColouredFlow.Runner.Storage.insert_enactment(%{
          flow_id: flow_id,
          initial_markings: ApprovalFlow.__cpn__(:initial_markings)
        })

      enactment_id = InMemory.enactment(enactment, :id)

      page = mount_store(topic)
      assigns = Musubi.Testing.assigns(page)

      assert Map.has_key?(assigns.row_index, enactment_id)
      row = assigns.row_index[enactment_id]
      assert %EnactmentRow{} = row
      assert row.flow_id == flow_id
      # ApprovalFlow's seeded name resolves; if the cpnet match misses,
      # `seeded_name_for/1` returns "" — assert non-nil so a regression in
      # the lookup surface is visible.
      assert is_binary(row.flow_name)
      assert row.state == :running
      assert assigns.running_count >= 1
    end
  end

  describe "PubSub event routing" do
    test "lifecycle :enactment_terminate flips row state in-place",
         %{topic: topic} do
      flow_record = InMemory.insert_flow!(ApprovalFlow.cpnet())
      flow_id = InMemory.flow(flow_record, :id)

      {:ok, enactment} =
        ColouredFlow.Runner.Storage.insert_enactment(%{
          flow_id: flow_id,
          initial_markings: ApprovalFlow.__cpn__(:initial_markings)
        })

      enactment_id = InMemory.enactment(enactment, :id)

      page = mount_store(topic)
      assigns_before = Musubi.Testing.assigns(page)
      assert assigns_before.row_index[enactment_id].state == :running

      terminate_event = %Event{
        topic: :enactments,
        kind: :enactment_terminate,
        enactment_id: enactment_id,
        enactment_version: 2,
        seq: 1,
        occurred_at: DateTime.utc_now(),
        payload: %{}
      }

      broadcast!(topic, terminate_event)
      assigns = Musubi.Testing.assigns(page)

      assert assigns.row_index[enactment_id].state == :terminated
      assert assigns.terminated_count >= 1
      assert assigns.last_seq == %{enactment_id => 1}
    end

    test ":enactment_exception flips row state to :exception",
         %{topic: topic} do
      flow_record = InMemory.insert_flow!(ApprovalFlow.cpnet())
      flow_id = InMemory.flow(flow_record, :id)

      {:ok, enactment} =
        ColouredFlow.Runner.Storage.insert_enactment(%{
          flow_id: flow_id,
          initial_markings: ApprovalFlow.__cpn__(:initial_markings)
        })

      enactment_id = InMemory.enactment(enactment, :id)

      page = mount_store(topic)

      event = %Event{
        topic: :enactments,
        kind: :enactment_exception,
        enactment_id: enactment_id,
        enactment_version: 2,
        seq: 1,
        occurred_at: DateTime.utc_now(),
        payload: %{}
      }

      broadcast!(topic, event)
      assigns = Musubi.Testing.assigns(page)

      assert assigns.row_index[enactment_id].state == :exception
      assert assigns.exception_count >= 1
    end

    test "lazy-loads a row for an :enactment_start event the seed did not see",
         %{topic: topic} do
      page = mount_store(topic)
      assigns_before = Musubi.Testing.assigns(page)

      flow_record = InMemory.insert_flow!(ApprovalFlow.cpnet())
      flow_id = InMemory.flow(flow_record, :id)

      {:ok, enactment} =
        ColouredFlow.Runner.Storage.insert_enactment(%{
          flow_id: flow_id,
          initial_markings: ApprovalFlow.__cpn__(:initial_markings)
        })

      enactment_id = InMemory.enactment(enactment, :id)
      refute Map.has_key?(assigns_before.row_index, enactment_id)

      event = %Event{
        topic: :enactments,
        kind: :enactment_start,
        enactment_id: enactment_id,
        enactment_version: 1,
        seq: 1,
        occurred_at: DateTime.utc_now(),
        payload: %{}
      }

      broadcast!(topic, event)
      assigns = Musubi.Testing.assigns(page)

      assert Map.has_key?(assigns.row_index, enactment_id)
      assert assigns.row_index[enactment_id].state == :running
      assert assigns.row_index[enactment_id].flow_id == flow_id
    end

    test "drops stale events whose seq is less than the last applied seq",
         %{topic: topic} do
      flow_record = InMemory.insert_flow!(ApprovalFlow.cpnet())
      flow_id = InMemory.flow(flow_record, :id)

      {:ok, enactment} =
        ColouredFlow.Runner.Storage.insert_enactment(%{
          flow_id: flow_id,
          initial_markings: ApprovalFlow.__cpn__(:initial_markings)
        })

      enactment_id = InMemory.enactment(enactment, :id)

      page = mount_store(topic)

      fresh = %Event{
        topic: :enactments,
        kind: :enactment_terminate,
        enactment_id: enactment_id,
        enactment_version: 2,
        seq: 5,
        occurred_at: DateTime.utc_now(),
        payload: %{}
      }

      stale = %Event{fresh | seq: 3, kind: :enactment_start}

      broadcast!(topic, fresh)
      assigns_fresh = Musubi.Testing.assigns(page)
      assert assigns_fresh.row_index[enactment_id].state == :terminated

      broadcast!(topic, stale)
      assigns = Musubi.Testing.assigns(page)

      # Stale start did NOT flip back to :running; last_seq stayed at 5.
      assert assigns.row_index[enactment_id].state == :terminated
      assert assigns.last_seq == %{enactment_id => 5}
    end

    test "non-lifecycle events are ignored", %{topic: topic} do
      page = mount_store(topic)
      eid = Ecto.UUID.generate()

      event = %Event{
        topic: :inbox,
        kind: :produce_workitems_stop,
        enactment_id: eid,
        enactment_version: 1,
        seq: 1,
        occurred_at: DateTime.utc_now(),
        payload: %{operation: :produce_workitems, workitems: []}
      }

      broadcast!(topic, event)
      assigns = Musubi.Testing.assigns(page)
      assert assigns.last_seq == %{}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp discriminator(context),
    do: Integer.to_string(:erlang.phash2({context.module, context.test}))

  defp mount_store(topic) do
    Musubi.Testing.mount(EnactmentListStore, %{"topic" => topic})
  end

  defp broadcast!(topic, %Event{} = event) do
    :ok = Phoenix.PubSub.broadcast(@pubsub, topic, {:cf_event, event})
  end
end
