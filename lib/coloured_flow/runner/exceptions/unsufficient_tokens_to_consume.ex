defmodule ColouredFlow.Runner.Exceptions.UnsufficientTokensToConsume do
  @moduledoc """
  This exception is raised when there are not enough tokens to consume. For
  example, when the binding elements of the starting workitems require more tokens
  than are available in the place marking.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
    field :place, Place.name()
    field :tokens, Marking.tokens()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    The place #{exception.place} in the enactment with
    ID #{exception.enactment_id} does not have enough tokens to consume.
    The place tokens are #{inspect(exception.tokens)}.
    """
  end
end
