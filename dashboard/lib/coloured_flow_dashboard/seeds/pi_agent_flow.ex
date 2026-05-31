defmodule ColouredFlowDashboard.Seeds.PiAgentFlow do
  @moduledoc """
  Demo flow adapted (CPN-shape only — no driver / mock-LLM hooks) from
  `examples/pi_agent.livemd` "Pi Agent A — Simple ReAct" net. The point of
  seeding it here is to exercise the diagram + replay surface against a
  net that has:

    * Multi-token markings: `:dialog` carries a list-of-messages token
      that grows as transitions fire.
    * Atom unions: `tool_name` and `role` are pure colour-set enums.
    * A signal-typed `:ready` synchroniser sandwiched between three
      transitions.

  Initial markings:

    * `:dialog`  — one token: the initial user message.
    * `:ready`   — one unit token so `:think_tool` / `:think_answer` are
      both enabled at start.

  Operator-supplied free variables (`tc`, `tr`, `ans`) flow through the
  M5 structured form. No action functions: the dashboard is the driver,
  one workitem at a time.
  """

  use ColouredFlow.DSL

  name "Pi Agent A — Simple ReAct"
  version "1.0.0"

  colset role() :: :user | :assistant | :tool
  colset msg() :: {role(), binary()}
  colset dialog() :: list(msg())
  colset tool_name() :: :read | :grep | :ls | :write | :edit | :bash
  colset tool_call() :: {tool_name(), binary()}
  colset tool_result() :: binary()
  colset answer() :: binary()
  colset signal() :: {}

  var d :: dialog()
  var tc :: tool_call()
  var tr :: tool_result()
  var ans :: answer()
  var s :: signal()

  place :dialog, :dialog
  place :ready, :signal
  place :pending_call, :tool_call
  place :tool_result, :tool_result
  place :answer, :answer

  initial_marking :dialog,
                  ColouredFlow.MultiSet.new([[{:user, "What's in lib/?"}]])

  initial_marking :ready, ~MS[{}]

  transition :think_tool do
    input :ready, bind({1, s})
    input :dialog, bind({1, d})

    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    output :dialog, {1, d ++ [{:assistant, "calling tool"}]}
    output :pending_call, {1, tc}
  end

  transition :think_answer do
    input :ready, bind({1, s})
    input :dialog, bind({1, d})

    output :dialog, {1, d}
    output :answer, {1, ans}
  end

  transition :run_tool do
    input :pending_call, bind({1, tc})

    output :tool_result, {1, tr}
  end

  transition :merge_result do
    input :dialog, bind({1, d})
    input :tool_result, bind({1, tr})

    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    output :dialog, {1, d ++ [{:tool, tr}]}
    output :ready, {1, {}}
  end

  termination do
    on_markings do
      match?(%{"answer" => _}, markings)
    end
  end
end
