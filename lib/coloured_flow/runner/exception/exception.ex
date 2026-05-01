defmodule ColouredFlow.Runner.Exception do
  @moduledoc """
  The enactment may be stopped due to an exception.

  ## Reasons

  | reason                             | description                                                                                                                      |
  | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
  | `:termination_criteria_evaluation` | The termination-criteria expression failed to compile or returned a non-boolean value.                                           |
  | `:state_drift`                     | The enactment's in-memory state diverged from storage (`unexpected_updated_rows`, `Multi` rollback during workitem persistence). |
  | `:snapshot_corrupt`                | The persisted snapshot could not be decoded (codec failure, unexpected term shape).                                              |
  | `:replay_failed`                   | One of the persisted occurrences could not be applied during catch-up replay (codec failure, broken multiset operation).         |
  | `:enactment_data_missing`          | A row that the enactment depends on (`enactments`, `flows`) was not found at boot.                                               |
  | `:cpnet_corrupt`                   | The persisted Coloured Petri Net definition could not be decoded.                                                                |

  See `error_handling_design.md` for the full classification.
  """

  reason = ~w[
    termination_criteria_evaluation
    state_drift
    snapshot_corrupt
    replay_failed
    enactment_data_missing
    cpnet_corrupt
  ]a
  @type reason() :: unquote(ColouredFlow.Types.make_sum_type(reason))

  @spec __reasons__() :: [reason()]
  def __reasons__, do: unquote(reason)
end
