defmodule ColouredFlow.Runner.Exceptions.EnactmentTimeout do
  @moduledoc """
  Raised when a public Runner API call to an enactment exceeds the configured call
  timeout. The enactment process may still be alive and may eventually complete
  the requested operation; the caller has merely stopped waiting.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
    field :timeout, non_neg_integer() | :infinity
    field :error_code, atom(), default: :enactment_timeout
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The call to enactment #{exception.enactment_id} timed out after #{exception.timeout}ms.
    """
  end
end
