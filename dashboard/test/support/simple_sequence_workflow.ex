defmodule ColouredFlowDashboard.Test.SimpleSequenceWorkflow do
  @moduledoc """
  Tiny pass-through CPN used by `ColouredFlowDashboard.TelemetryBridgeTest`'s
  integration smoke. One token enters `:input`, the `pass` transition fires
  once, and the token lands in `:output` — enough to drive the full enactment
  lifecycle + workitem operation telemetry through the bridge.
  """

  use ColouredFlow.DSL

  name "TelemetryBridge integration smoke"

  colset int() :: integer()

  var x :: int()

  place :input, :int
  place :output, :int

  initial_marking :input, ~MS[1]

  transition :pass do
    input :input, bind({1, x})
    output :output, {1, x}
  end
end
