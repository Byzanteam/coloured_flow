defmodule ColouredFlowDashboard.Seeds.TrafficLightFlow do
  @moduledoc """
  Demo flow adapted from `examples/traffic_light.livemd`. Replicated locally
  (the dashboard MUST NOT depend on the example livemd code) so the CPN
  shape demonstrates a larger choreography with cross-token concurrency:

    * Two synchronised intersections (`ew`, `ns`) each cycle through
      `red → green → yellow → red`.
    * A pair of `safe_*` semaphores prevent both directions from greening
      simultaneously — only one `:turn_green_*` can fire at a time.
    * Six transitions, eight places. No action functions: the dashboard
      replay surface only needs the CPN structure; firing is driven by
      operators (or by the M7b autoplay) one workitem at a time.

  Unlike `ApprovalFlow`, transitions consume + produce `signal()` tokens
  (the `unit`-like product type). That keeps the M4 diagram token-counts
  trivially readable while still exercising multi-place markings.
  """

  use ColouredFlow.DSL

  name "TrafficLight Demo"
  version "1.0.0"

  colset signal() :: {}

  var s :: signal()

  place :red_ew, :signal
  place :green_ew, :signal
  place :yellow_ew, :signal
  place :red_ns, :signal
  place :green_ns, :signal
  place :yellow_ns, :signal
  place :safe_ew, :signal
  place :safe_ns, :signal

  initial_marking :red_ew, ~MS[{}]
  initial_marking :red_ns, ~MS[{}]
  initial_marking :safe_ew, ~MS[{}]

  transition :turn_green_ew do
    input :red_ew, bind({1, s})
    input :safe_ew, bind({1, s})
    output :green_ew, {1, s}
  end

  transition :turn_yellow_ew do
    input :green_ew, bind({1, s})
    output :yellow_ew, {1, s}
  end

  transition :turn_red_ew do
    input :yellow_ew, bind({1, s})
    output :red_ew, {1, s}
    output :safe_ns, {1, s}
  end

  transition :turn_green_ns do
    input :red_ns, bind({1, s})
    input :safe_ns, bind({1, s})
    output :green_ns, {1, s}
  end

  transition :turn_yellow_ns do
    input :green_ns, bind({1, s})
    output :yellow_ns, {1, s}
  end

  transition :turn_red_ns do
    input :yellow_ns, bind({1, s})
    output :red_ns, {1, s}
    output :safe_ew, {1, s}
  end
end
