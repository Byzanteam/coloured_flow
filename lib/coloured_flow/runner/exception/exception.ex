defmodule ColouredFlow.Runner.Exception do
  @moduledoc """
  The enactment may record exceptional events.

  Each event becomes a row in `enactment_logs` with `kind = :exception`, written
  through `ColouredFlow.Runner.Storage.exception_occurs/3`. Writing an exception
  log row does **not** flip `enactments.state`; the state column is updated only
  by `ensure_runnable/1` (when the circuit breaker trips), `retry_enactment/2`,
  and `terminate_enactment/4`.

  ## Reasons

  | reason                          | description                                                                               |
  | ------------------------------- | ----------------------------------------------------------------------------------------- |
  | `:invalid_termination_criteria` | The termination-criteria expression failed to compile or returned a non-boolean value.    |
  | `:snapshot_corrupt`             | The persisted snapshot could not be decoded. Self-heal: replay from initial markings.     |
  | `:abnormal_exit`                | An abnormal `terminate/2` exit. Counted toward the consecutive-exception circuit breaker. |
  """

  reasons = ~w[invalid_termination_criteria snapshot_corrupt abnormal_exit]a

  @type reason() :: unquote(ColouredFlow.Types.make_sum_type(reasons))

  @spec __reasons__() :: [reason()]
  def __reasons__, do: unquote(reasons)
end
