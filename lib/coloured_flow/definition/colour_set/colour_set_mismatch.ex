defmodule ColouredFlow.Definition.ColourSet.ColourSetMismatch do
  @moduledoc """
  The value of a colour set does not match the expected type.
  """

  use TypedStructor

  @message "The value of the colour set does not match the expected type."

  typed_structor definer: :defexception, enforce: true do
    field :message, String.t(), default: @message
    field :colour_set, ColouredFlow.Definition.ColourSet.t()
    field :value, term()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    "#{exception.message} (colour set: #{inspect(exception.colour_set)}, value: #{inspect(exception.value)})"
  end
end
