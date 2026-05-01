defmodule ColouredFlow.Runner.Exceptions.EnactmentNotRunning do
  @moduledoc """
  Raised when a public Runner API call targets an enactment that is not currently
  running. Possible causes include the enactment never having been started, the
  enactment having terminated, having transitioned to `:exception`, or being in
  the middle of a graceful shutdown when the call arrived.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Storage

  @type reason() :: :not_started | :shutting_down | :stopped_during_call | :unknown

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
    field :reason, reason(), default: :unknown
    field :error_code, atom(), default: :enactment_not_running
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The enactment with ID #{exception.enactment_id} is not running (#{exception.reason}).
    """
  end
end
