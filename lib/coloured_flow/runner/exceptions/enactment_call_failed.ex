defmodule ColouredFlow.Runner.Exceptions.EnactmentCallFailed do
  @moduledoc """
  Raised when a public Runner API call to an enactment fails with an exit reason
  that does not map to a more specific exception (`EnactmentNotRunning` or
  `EnactmentTimeout`). Carries the original exit reason for postmortem use.

  Common cases include the called process being killed (`:killed`), the remote
  node going down (`{:nodedown, node}`), or any other unhandled `GenServer.call`
  exit pattern.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
    field :reason, term()
    field :error_code, atom(), default: :enactment_call_failed
  end

  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The call to enactment #{exception.enactment_id} failed with reason: #{inspect(exception.reason)}.
    """
  end
end
