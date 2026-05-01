defmodule ColouredFlow.Runner do
  @moduledoc """
  The ColouredFlow runner.

  ## API contract

  All public functions in this module return either an `:ok` shape or an
  `{:error, exception}` tuple where `exception` is a typed runner exception (see
  `ColouredFlow.Runner.Errors` for classification). Callers never have to handle
  raw process-exit signals — the runtime translates `GenServer.call/3` exits
  (`:noproc`, `:timeout`, `:shutdown`, `:nodedown`, …) into `EnactmentNotRunning`,
  `EnactmentTimeout`, or `EnactmentCallFailed`.

  ### Breaking change history

  - `terminate_enactment/2` previously returned `:ok` and raised on a storage
    failure. It now returns `:ok | {:error, Exception.t()}`, matching the rest of
    the API. Callers that previously pattern-matched on a bare `:ok` should switch
    to `case`/`with`.
  """

  alias ColouredFlow.Runner.Enactment.Supervisor, as: EnactmentSupervisor
  alias ColouredFlow.Runner.Enactment.WorkitemTransition

  defdelegate insert_enactment(params), to: ColouredFlow.Runner.Storage
  defdelegate start_enactment(enactment_id), to: EnactmentSupervisor

  @doc """
  Forcibly terminate the enactment with the given id.

  Returns `:ok` on success. Returns `{:error, exception}` if the enactment is not
  running, the call times out, or the persistence layer fails to record the
  termination.
  """
  @spec terminate_enactment(
          ColouredFlow.Runner.Storage.enactment_id(),
          options :: [message: String.t()]
        ) :: :ok | {:error, Exception.t()}
  defdelegate terminate_enactment(enactment_id, options \\ []), to: EnactmentSupervisor

  defdelegate start_workitem(enactment_id, workitem_id), to: WorkitemTransition
  defdelegate start_workitems(enactment_id, workitem_ids), to: WorkitemTransition

  defdelegate complete_workitem(enactment_id, workitem_id_and_outputs), to: WorkitemTransition
  defdelegate complete_workitems(enactment_id, workitem_ids_and_outputs), to: WorkitemTransition
end
