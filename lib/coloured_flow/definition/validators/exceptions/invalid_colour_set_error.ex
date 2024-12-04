defmodule ColouredFlow.Definition.Validators.Exceptions.InvalidColourSetError do
  @moduledoc """
  This exception is raised when the colour set is invalid.
  """

  use TypedStructor

  @type reason() ::
          :built_in_type
          | :invalid_map_key
          | :invalid_enum_item
          | :invalid_union_tag
          | :recursive_type
          | :undefined_type
          | :unsupporetd_type

  typed_structor definer: :defexception, enforce: true do
    field :message, String.t()
    field :reason, reason()
    field :descr, term()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The colour set is invalid, due to #{inspect(exception.reason)}.

    #{exception.message}

    descr: #{inspect(exception.descr)}
    """
  end
end
