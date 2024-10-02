defmodule ColouredFlow.Enactment.Occurrence do
  @moduledoc """
  The occurrence of a transition in an enabled binding element.
  """

  use TypedStructor

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking

  @type free_binding() :: [BindingElement.binding()]

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :binding_element, BindingElement.t(), doc: "The enabled binding element."

    field :free_binding, free_binding(),
      doc: """
      A free assignments(aka binding) is an output arc variable,
      that has not been bound to an input arc or to the guard.

      The free assignments must be bound after the transition is fired,
      and they are bound to the outputs of the transition action.

      The sets of bound_assignments(that is `t:ColouredFlow.Enactment.BindingElement.binding/0`) and free_binding are mutually exclusive.
      """

    field :to_produce, [Marking.t()],
      doc: "The markings to be produced after the transition fired."
  end
end
