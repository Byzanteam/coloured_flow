defmodule ColouredFlow.Runner.Exception do
  @moduledoc """
  The enactment may record exceptional events.

  Each event becomes a row in `enactment_logs`. The `reason` discriminates the
  cause; the `state` column on the same row indicates whether the event is fatal
  (state=`:exception`) or non-fatal (state=`:running`, used for recovery and crash
  records the runner consumes during boot).

  ## Reasons

  | reason                             | row state    | description                                                                                              |
  | ---------------------------------- | ------------ | -------------------------------------------------------------------------------------------------------- |
  | `:termination_criteria_evaluation` | `:exception` | The termination-criteria expression failed to compile or returned a non-boolean value.                   |
  | `:state_drift`                     | `:exception` | The enactment's in-memory state diverged from storage (`:unexpected_updated_rows` or Multi rollback).    |
  | `:snapshot_corrupt`                | `:running`   | The persisted snapshot could not be decoded. Self-heal: reset snapshot and replay from initial markings. |
  | `:crash`                           | `:running`   | An abnormal `terminate/2` exit. Counted toward the consecutive-crash circuit breaker.                    |
  | `:restart_loop`                    | `:exception` | 3 consecutive `:crash` events without an intervening occurrence. Init aborts via `:ignore`.              |
  """

  reasons = ~w[
    termination_criteria_evaluation
    state_drift
    snapshot_corrupt
    crash
    restart_loop
  ]a
  @type reason() :: unquote(ColouredFlow.Types.make_sum_type(reasons))

  @spec __reasons__() :: [reason()]
  def __reasons__, do: unquote(reasons)

  fatal_reasons = ~w[
    termination_criteria_evaluation
    state_drift
    restart_loop
  ]a
  @type fatal_reason() :: unquote(ColouredFlow.Types.make_sum_type(fatal_reasons))

  @doc "Reasons that flip `enactments.state` to `:exception`."
  @spec __fatal_reasons__() :: [fatal_reason()]
  def __fatal_reasons__, do: unquote(fatal_reasons)
end
