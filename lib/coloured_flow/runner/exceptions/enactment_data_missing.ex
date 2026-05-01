defmodule ColouredFlow.Runner.Exceptions.EnactmentDataMissing do
  @moduledoc """
  Raised when an enactment cannot find a row it needs at boot — most commonly the
  `enactments` row itself, or the linked `flows` row, has been deleted.

  Surfaced as a Tier 2 enactment-fatal error during boot.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
    field :missing, atom()
    field :error_code, atom(), default: :enactment_data_missing
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    Enactment #{exception.enactment_id} cannot start: required `#{exception.missing}` row not found.
    """
  end
end
