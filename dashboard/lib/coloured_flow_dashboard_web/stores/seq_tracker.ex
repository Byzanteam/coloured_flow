defmodule ColouredFlowDashboardWeb.Stores.SeqTracker do
  @moduledoc """
  Per-enactment monotonic seq drop-stale helper shared by every Musubi root
  store that consumes `ColouredFlowDashboard.TelemetryBridge.Event` streams.

  The bridge allocates a strictly-increasing `:seq` per event in the
  runner's serialised `:telemetry.execute/3` call before the per-event
  `Task.Supervisor` fan-out. Tasks then race during delivery, so a late
  `produce_workitems_stop` can arrive after a `complete_workitems_stop` for
  the same enactment. Each consumer keeps a `%{enactment_id => last_seq}`
  map in its socket assigns and drops every event whose `seq` is less than
  or equal to the highest already applied for the same enactment.

  Two events with `seq == 0` always pass through — that's the
  test-constructed / unscoped sentinel `Event` documents.
  """

  alias ColouredFlowDashboard.TelemetryBridge.Event

  @type tracker() :: %{optional(Event.enactment_id()) => non_neg_integer()}

  @doc "Returns true when `event.seq` is older than the recorded seq for its enactment."
  @spec stale?(Event.t(), tracker()) :: boolean()
  def stale?(%Event{enactment_id: eid, seq: seq}, tracker)
      when is_binary(eid) and is_integer(seq) and seq > 0 do
    case Map.get(tracker, eid) do
      nil -> false
      prev when is_integer(prev) -> seq <= prev
    end
  end

  def stale?(%Event{}, _tracker), do: false

  @doc "Returns the tracker with `event.seq` recorded for its enactment."
  @spec bump(tracker(), Event.t()) :: tracker()
  def bump(tracker, %Event{enactment_id: eid, seq: seq})
      when is_binary(eid) and is_integer(seq) and seq > 0 do
    Map.put(tracker, eid, seq)
  end

  def bump(tracker, %Event{}), do: tracker
end
