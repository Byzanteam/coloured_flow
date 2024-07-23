defmodule ColouredFlow.Enactment.BindingElement do
  @moduledoc """
  A binding element comprises a transition and a set of bound and free assignments.

  A binding element is considered enabled if:
  1. The guard of the transition is satisfied.
  2. There are sufficient tokens on the input places of the transition.

  The sets of bound_assignments and free_assignments are mutually exclusive.
  """

  use TypedStructor

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable

  typed_structor enfore: true do
    plugin TypedStructor.Plugins.DocFields

    field :transition, Transition.name()

    field :bound_assignments, {Variable.name(), ColourSet.value()},
      doc: """
      A bound assignments(aka binding) is an output arc variable
      that has been bound to an input arc or to the guard.
      """

    field :free_assignments, {Variable.name(), ColourSet.value()},
      doc: """
      A free assignments(aka binding) is an output arc variable,
      that has not been bound to an input arc or to the guard.

      The free assignments must be bound after the transition is fired,
      and they are bound to the outputs of the transition action.
      """
  end
end
