defmodule ColouredFlow.Enactment.Occurrence do
  @moduledoc """
  The occurrence of a transition in an enabled binding element.
  """

  use TypedStructor

  alias ColouredFlow.Enactment.BindingElement

  typed_structor enforce: true do
    field :step, pos_integer(),
      doc: "The step number of the occurrence, it is used to order the occurrences."

    field :binding_elemnt, BindingElement.t(), doc: "The enabled binding element."
  end
end
