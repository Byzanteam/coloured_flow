defmodule ColouredFlow.Definition.ColourSet.ColourSetMismatch do
  @moduledoc """
  The value of a colour set does not match the expected type.
  """

  defexception [:message, :colour_set, :value]

  @message "The value of the colour set does not match the expected type."

  @impl Exception
  def exception(opts) do
    colour_set = Keyword.fetch!(opts, :colour_set)
    value = Keyword.fetch!(opts, :value)
    message = Keyword.get(opts, :message, @message)

    %__MODULE__{message: message, colour_set: colour_set, value: value}
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    "#{exception.message} (colour set: #{inspect(exception.colour_set)}, value: #{inspect(exception.value)})"
  end
end
