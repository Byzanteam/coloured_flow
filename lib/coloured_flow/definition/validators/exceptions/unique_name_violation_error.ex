defmodule ColouredFlow.Definition.Validators.Exceptions.UniqueNameViolationError do
  @moduledoc """
  This exception is raised when a duplicate name violation is detected by the `ColouredFlow.Definition.Validators.UniqueNameValidator`.
  """

  use TypedStructor

  typed_structor definer: :defexception, enforce: true do
    field :scope, :colour_set | :variable | :place | :transition
    field :name, String.t() | atom()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The name `#{inspect(exception.name)}` is not unique within the #{exception.scope}.
    """
  end
end
