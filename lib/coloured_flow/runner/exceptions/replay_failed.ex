defmodule ColouredFlow.Runner.Exceptions.ReplayFailed do
  @moduledoc """
  Raised when an occurrence in the persisted event stream cannot be applied during
  catch-up replay — typically a codec failure on the occurrence row or an
  inconsistency surfaced by `MultiSet` operations.

  Surfaced as a Tier 2 enactment-fatal error during boot.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
    field :underlying, Exception.t() | term(), enforce: false
    field :error_code, atom(), default: :replay_failed
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    Catch-up replay failed for enactment #{exception.enactment_id}.
    Underlying: #{inspect(exception.underlying)}
    """
  end
end
