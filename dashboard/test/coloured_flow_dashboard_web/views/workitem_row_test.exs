defmodule ColouredFlowDashboardWeb.Views.WorkitemRowTest do
  # Verifies the `binding_pairs` wire shape emitted by `InboxStore`'s row
  # builder. We exercise the public mount + bridge-broadcast surface so the
  # test pins the actual production code path (not a hand-rolled copy of
  # `binding_pairs/1`).
  use ColouredFlowDashboard.DataCase, async: false

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Runner.Enactment.Workitem, as: RunnerWorkitem
  alias ColouredFlowDashboard.TelemetryBridge.Event
  alias ColouredFlowDashboardWeb.Stores.InboxStore
  alias ColouredFlowDashboardWeb.Views.BindingPair
  alias ColouredFlowDashboardWeb.Views.WorkitemRow

  @pubsub :coloured_flow_dashboard_pubsub

  test "binding_pairs carries one %BindingPair{} per bound variable, inspect/1-rendered values" do
    topic = "cf-test-workitem-row-#{System.unique_integer([:positive])}:inbox"

    flow_cache = :workitem_row_view_test_flow_cache

    page =
      Musubi.Testing.mount(InboxStore, %{
        "pubsub_name" => @pubsub,
        "topic" => topic,
        "flow_cache" => flow_cache
      })

    enactment_id = Ecto.UUID.generate()
    wi_id = Ecto.UUID.generate()

    event = %Event{
      topic: :inbox,
      kind: :produce_workitems_stop,
      enactment_id: enactment_id,
      enactment_version: 1,
      occurred_at: DateTime.utc_now(),
      payload: %{
        operation: :produce_workitems,
        workitems: [
          %RunnerWorkitem{
            id: wi_id,
            state: :enabled,
            binding_element: %BindingElement{
              transition: "approve",
              binding: [
                {:verdict, :approve},
                {:note, "looks good"},
                {:pair, {1, true}}
              ],
              to_consume: []
            }
          }
        ]
      }
    }

    :ok = Phoenix.PubSub.broadcast(@pubsub, topic, {:cf_event, event})

    assigns = Musubi.Testing.assigns(page)
    row = Map.fetch!(assigns.workitem_rows, wi_id)

    assert %WorkitemRow{binding_pairs: pairs, binding_summary: summary} = row

    assert pairs == [
             %BindingPair{name: "verdict", value: ":approve"},
             %BindingPair{name: "note", value: ~s("looks good")},
             %BindingPair{name: "pair", value: "{1, true}"}
           ]

    assert summary == ~s(verdict = :approve, note = "looks good", pair = {1, true})
  end
end
