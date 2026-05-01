defmodule ColouredFlow.Runner.Exceptions.SnapshotCorrupt do
  @moduledoc """
  Raised when the persisted enactment snapshot cannot be decoded — typically a
  codec failure or an unexpected term shape inside `markings`.

  Surfaced as a Tier 2 enactment-fatal error during boot.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
    field :underlying, Exception.t() | term(), enforce: false
    field :error_code, atom(), default: :snapshot_corrupt
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The persisted snapshot for enactment #{exception.enactment_id} could not be decoded.
    Underlying: #{inspect(exception.underlying)}
    """
  end
end
