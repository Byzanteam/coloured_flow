defmodule ColouredFlow.Runner.Exceptions.SnapshotCorrupt do
  @moduledoc """
  The persisted snapshot row could not be decoded. The runner self-heals by
  deleting the corrupt row and replaying from the enactment's initial markings.

  This exception is recorded as a non-fatal log entry; the enactment state stays
  `:running`.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
    field :underlying, Exception.t()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    Snapshot for enactment #{inspect(exception.enactment_id)} could not be \
    decoded. Falling back to a full replay from the initial markings. \
    Underlying: #{Exception.message(exception.underlying)}\
    """
  end
end
