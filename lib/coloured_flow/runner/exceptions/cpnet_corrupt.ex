defmodule ColouredFlow.Runner.Exceptions.CpnetCorrupt do
  @moduledoc """
  Raised when the persisted Coloured Petri Net definition for an enactment cannot
  be decoded — typically a codec failure on `flows.definition` or its embedded
  objects.

  Surfaced as a Tier 2 enactment-fatal error.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
    field :underlying, Exception.t() | term(), enforce: false
    field :error_code, atom(), default: :cpnet_corrupt
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The Coloured Petri Net definition for enactment #{exception.enactment_id} could not be decoded.
    Underlying: #{inspect(exception.underlying)}
    """
  end
end
