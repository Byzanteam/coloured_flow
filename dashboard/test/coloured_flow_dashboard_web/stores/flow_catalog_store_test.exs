defmodule ColouredFlowDashboardWeb.Stores.FlowCatalogStoreTest do
  # `async: false` matches `InboxStoreTest` rationale: the store's mount
  # reads either Repo or InMemory tables (cross-process sandbox concerns
  # for the spawned page server) and the integration assertions touch the
  # globally-named `ColouredFlow.Runner.Storage.InMemory` ETS tables.
  use ColouredFlowDashboard.DataCase, async: false

  alias ColouredFlow.Runner.Storage.InMemory
  alias ColouredFlowDashboard.Seed
  alias ColouredFlowDashboard.Seeds.ApprovalFlow
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboardWeb.Stores.FlowCatalogStore

  require InMemory

  @pubsub :coloured_flow_dashboard_pubsub

  setup context do
    topic = "cf-test-#{discriminator(context)}:flows"

    # Carry-over from `SeedTest`: scrub any `:persistent_term` left by an
    # earlier suite so this test's run/1 path is independent. We do not
    # actually seed via `Seed.run/1` here, but the test's :start_enactment
    # paths share the same registry namespace.
    cleanup_seed_persistent_terms()

    {:ok, topic: topic}
  end

  describe "mount/2" do
    # The test environment's `ColouredFlow.Runner.Storage.InMemory` ETS
    # tables are app-singleton across the suite, so earlier tests can leave
    # flow / enactment rows visible to a later mount. Assertions below are
    # additive (contains the flow inserted by THIS test) rather than
    # exact-cardinality.

    test "renders an empty render placeholder for the stream slot", %{topic: topic} do
      page = mount_store(topic)

      assert %{flows: %Musubi.Stream.Placeholder{name: :flows}} =
               Musubi.Testing.render(page)
    end

    test "lists a flow inserted via the InMemory backend", %{topic: topic} do
      before_count = current_total_flows()
      flow_record = InMemory.insert_flow!(ApprovalFlow.cpnet())
      flow_id = InMemory.flow(flow_record, :id)

      page = mount_store(topic)
      assigns = Musubi.Testing.assigns(page)

      assert assigns.counts.total_flows == before_count + 1
      assert MapSet.member?(assigns.flow_ids, flow_id)
    end

    test "live_enactments counts running enactments per flow", %{topic: topic} do
      before_live = current_total_live_enactments()
      flow_record = InMemory.insert_flow!(ApprovalFlow.cpnet())
      flow_id = InMemory.flow(flow_record, :id)

      {:ok, _enactment} =
        ColouredFlow.Runner.Storage.insert_enactment(%{
          flow_id: flow_id,
          initial_markings: ApprovalFlow.__cpn__(:initial_markings)
        })

      page = mount_store(topic)
      assigns = Musubi.Testing.assigns(page)

      assert assigns.counts.total_live_enactments == before_live + 1
      assert MapSet.member?(assigns.flow_ids, flow_id)
    end
  end

  describe ":start_enactment command" do
    test "happy path: ok reply + enactment_id + Runner.start_enactment fires", %{
      topic: topic
    } do
      flow_record = InMemory.insert_flow!(ApprovalFlow.cpnet())
      flow_id = InMemory.flow(flow_record, :id)

      page = mount_store(topic)

      assert {:ok, %{code: :ok, enactment_id: enactment_id}} =
               Musubi.Testing.dispatch_command(page, :start_enactment, %{flow_id: flow_id})

      assert is_binary(enactment_id)

      via =
        {:via, Registry, {ColouredFlow.Runner.Enactment.Registry, {:enactment, enactment_id}}}

      assert is_pid(GenServer.whereis(via))
    end

    test "returns :unknown_flow when the flow_id is not in storage", %{topic: topic} do
      page = mount_store(topic)

      bogus = Ecto.UUID.generate()

      assert {:ok, %{code: :unknown_flow, enactment_id: nil}} =
               Musubi.Testing.dispatch_command(page, :start_enactment, %{flow_id: bogus})
    end
  end

  describe ":refresh_catalog command" do
    test "rereads storage and stream-inserts newly visible flows", %{topic: topic} do
      page = mount_store(topic)
      assigns_before = Musubi.Testing.assigns(page)

      flow_record = InMemory.insert_flow!(ApprovalFlow.cpnet())
      flow_id = InMemory.flow(flow_record, :id)
      refute MapSet.member?(assigns_before.flow_ids, flow_id)

      assert {:ok, %{code: :ok}} =
               Musubi.Testing.dispatch_command(page, :refresh_catalog, %{})

      assigns = Musubi.Testing.assigns(page)
      assert MapSet.member?(assigns.flow_ids, flow_id)
      assert assigns.counts.total_flows == assigns_before.counts.total_flows + 1
    end
  end

  describe "PubSub event routing" do
    test "lifecycle event triggers a refresh", %{topic: topic} do
      page = mount_store(topic)
      before = Musubi.Testing.assigns(page)

      flow_record = InMemory.insert_flow!(ApprovalFlow.cpnet())
      flow_id = InMemory.flow(flow_record, :id)

      {:ok, _enactment} =
        ColouredFlow.Runner.Storage.insert_enactment(%{
          flow_id: flow_id,
          initial_markings: ApprovalFlow.__cpn__(:initial_markings)
        })

      eid = Ecto.UUID.generate()

      event = %Event{
        topic: :flows,
        kind: :enactment_start,
        enactment_id: eid,
        enactment_version: 1,
        seq: 1,
        occurred_at: DateTime.utc_now(),
        payload: %{}
      }

      broadcast!(topic, event)
      assigns = Musubi.Testing.assigns(page)

      assert assigns.counts.total_flows == before.counts.total_flows + 1
      assert assigns.last_seq == %{eid => 1}
    end

    test "drops stale events whose seq is less than the last applied seq", %{
      topic: topic
    } do
      page = mount_store(topic)

      eid = Ecto.UUID.generate()

      fresh = %Event{
        topic: :flows,
        kind: :enactment_start,
        enactment_id: eid,
        enactment_version: 2,
        seq: 5,
        occurred_at: DateTime.utc_now(),
        payload: %{}
      }

      stale = %Event{fresh | seq: 3, kind: :enactment_terminate}

      broadcast!(topic, fresh)
      Musubi.Testing.assigns(page)

      broadcast!(topic, stale)
      assigns = Musubi.Testing.assigns(page)

      # Stale event must not have bumped last_seq backward.
      assert assigns.last_seq == %{eid => 5}
    end

    test "non-lifecycle events are ignored even if their seq is fresh", %{topic: topic} do
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

      # No bump because we never accept non-lifecycle events.
      assert assigns.last_seq == %{}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp discriminator(context),
    do: Integer.to_string(:erlang.phash2({context.module, context.test}))

  defp mount_store(topic) do
    Musubi.Testing.mount(FlowCatalogStore, %{"topic" => topic})
  end

  defp broadcast!(topic, %Event{} = event) do
    :ok = Phoenix.PubSub.broadcast(@pubsub, topic, {:cf_event, event})
  end

  defp current_total_flows do
    InMemory |> Module.safe_concat("Flow") |> :ets.tab2list() |> length()
  rescue
    _error -> 0
  end

  defp current_total_live_enactments do
    InMemory |> Module.safe_concat("Enactment") |> :ets.tab2list() |> length()
  rescue
    _error -> 0
  end

  defp cleanup_seed_persistent_terms do
    for flow <- [
          ColouredFlowDashboard.Seeds.ApprovalFlow,
          ColouredFlowDashboard.Seeds.IncidentTriageFlow,
          ColouredFlowDashboard.Seeds.PiAgentFlow,
          ColouredFlowDashboard.Seeds.TrafficLightFlow
        ] do
      :persistent_term.erase({Seed, flow})
    end

    :ok
  end
end
