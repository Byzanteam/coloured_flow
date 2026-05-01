defmodule ColouredFlow.Runner.Errors do
  @moduledoc """
  Central error classification helpers for `ColouredFlow.Runner`.

  Pattern-matches on known exception modules and returns their tier, stable error
  code, and persisted reason mapping. New exception modules in the runner must be
  registered here.

  ## Tiers

  | Tier | Description                                                                                           |
  | ---- | ----------------------------------------------------------------------------------------------------- |
  | `1`  | Caller-visible operational errors. Returned from public API; enactment process state unchanged.       |
  | `2`  | Enactment-fatal errors. Persisted to `enactments.state = :exception`; gracefully stops the GenServer. |
  | `3`  | Transient infrastructure errors. Let it crash; supervisor restarts.                                   |
  | `4`  | Programmer errors. Should be caught by validators or compile-time checks.                             |

  ## Best-effort static dispatch

  All public functions in this module are **best-effort static dispatch on
  exception type**. They cannot infer the call site that produced the exception.
  The same exception type may belong to different tiers depending on context — for
  example, an `ArithmeticError` raised inside an arc expression during workitem
  completion is operationally Tier 1, but the same `ArithmeticError` raised by a
  buggy validator path is Tier 4.

  Foreign exceptions (anything not registered with `tier/1`) fall back to
  `tier == 3` and `error_code == :unknown`. Subscribers that need precise
  classification should rely on the **telemetry metadata** emitted at the call
  site (`:tier`, `:error_code`, `:exception_reason`, `:source_phase`) rather than
  calling these helpers on a returned `{:error, exception}` tuple.

  See `error_handling_design.md` at the repository root for the full
  specification.
  """

  alias ColouredFlow.Definition.ColourSet.ColourSetMismatch
  alias ColouredFlow.Expression.InvalidResult
  alias ColouredFlow.Runner.Exception, as: PersistedException
  alias ColouredFlow.Runner.Exceptions

  @doc """
  Returns the tier (1–4) of the given exception when surfaced through the runner.

  Tier classification is best-effort static — the same exception type may belong
  to different tiers depending on call site. Callers that need precise tiering
  should track it at the originating site rather than rely solely on this
  function.
  """
  @spec tier(Exception.t()) :: 1 | 2 | 3 | 4
  def tier(%Exceptions.NonLiveWorkitem{}), do: 1
  def tier(%Exceptions.InvalidWorkitemTransition{}), do: 1
  def tier(%Exceptions.UnsufficientTokensToConsume{}), do: 1
  def tier(%Exceptions.UnboundActionOutput{}), do: 1
  def tier(%Exceptions.EnactmentNotRunning{}), do: 1
  def tier(%Exceptions.EnactmentTimeout{}), do: 1
  def tier(%Exceptions.EnactmentCallFailed{}), do: 1
  def tier(%Exceptions.StoragePersistenceFailed{}), do: 1
  def tier(%ColourSetMismatch{}), do: 1
  def tier(%InvalidResult{}), do: 1
  def tier(_other), do: 3

  @doc """
  Returns the stable error code atom for the exception.

  For exceptions defined in this codebase the code is stored on the struct as the
  `:error_code` field. For foreign exceptions (e.g. `ArithmeticError`,
  `RuntimeError`) the function returns `:unknown` — callers should treat foreign
  exceptions as Tier 3 transient or Tier 4 programmer errors.
  """
  @spec error_code(Exception.t()) :: atom()
  def error_code(%{error_code: code}) when is_atom(code), do: code
  def error_code(_other), do: :unknown

  @doc """
  Returns `true` if the exception, when raised inside an enactment, should trigger
  a lifecycle `:exception` event (i.e. a persisted state transition to
  `:exception`).

  An exception is lifecycle-relevant when it has a corresponding persisted reason
  (see `to_persisted_reason/1`). Equivalent to `tier(exception) == 2` once Tier 2
  exception modules are registered, but the persisted-reason dispatch is the
  authoritative check.
  """
  @spec lifecycle?(Exception.t()) :: boolean()
  def lifecycle?(exception), do: not is_nil(to_persisted_reason(exception))

  @doc """
  Maps an exception to a persisted fatal reason atom, if one applies.

  The persisted reason is the value stored in `enactment_logs.exception.reason`
  (`Ecto.Enum` constrained to `ColouredFlow.Runner.Exception.__reasons__/0`).
  Returns `nil` for exceptions that should not produce a persisted enactment
  exception state.
  """
  @spec to_persisted_reason(Exception.t()) :: PersistedException.reason() | nil
  def to_persisted_reason(%InvalidResult{}), do: :termination_criteria_evaluation
  def to_persisted_reason(_other), do: nil
end
