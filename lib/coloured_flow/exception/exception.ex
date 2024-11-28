defmodule ColouredFlow.Exception do
  @moduledoc """
  The enactment may be stopped due to an exception.

  ## Reasons:

  ### `termination_criteria_evaluation`

  The termination criteria evaluation failed due to an invalid expression or evaluation result.
  """

  reason = ~w[termination_criteria_evaluation]a
  @type reason() :: unquote(ColouredFlow.Types.make_sum_type(reason))

  @spec __reasons__() :: [reason()]
  def __reasons__, do: unquote(reason)
end
