defmodule ColouredFlow.Validators.Exceptions.InvalidModuleError do
  @moduledoc """
  Exception raised when a module definition is invalid.
  """

  defexception [:reason, :module_name, :message]

  @type t() :: %__MODULE__{
          reason: atom(),
          module_name: binary() | nil,
          message: binary()
        }

  @impl Exception
  def exception(opts) do
    reason = Keyword.fetch!(opts, :reason)
    module_name = Keyword.get(opts, :module_name)
    message = Keyword.fetch!(opts, :message)

    %__MODULE__{
      reason: reason,
      module_name: module_name,
      message: message
    }
  end
end
