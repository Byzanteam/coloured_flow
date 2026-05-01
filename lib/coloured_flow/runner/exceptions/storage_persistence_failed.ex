defmodule ColouredFlow.Runner.Exceptions.StoragePersistenceFailed do
  @moduledoc """
  Raised when a Runner-public storage operation (such as
  `Runner.insert_enactment/1`) fails to persist its changes. Carries the failing
  operation name and a context map describing the failure for downstream
  diagnostics.
  """

  use TypedStructor

  typed_structor definer: :defexception, enforce: true do
    field :operation, atom()
    field :context, map()
    field :error_code, atom(), default: :storage_persistence_failed
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    Storage persistence failed for operation `#{exception.operation}`.
    Context: #{inspect(exception.context)}
    """
  end
end
