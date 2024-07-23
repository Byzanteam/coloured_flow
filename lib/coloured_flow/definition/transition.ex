defmodule ColouredFlow.Definition.Transition do
  @moduledoc """
  Transition t is enabled at a binding if there are tokens
  matching the values of the in-going arc inscriptions and
  the guard of t evaluates to true.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Expression

  @type name() :: binary()

  typed_structor enforce: true do
    field :name, name()

    field :guard, Expression.t(),
      default: nil,
      doc: """
      The guard of the transition.
      If not specified, the transition is always enabled.

      Note that, the guard can't refer to an unbound variable.
      """

    field :action, Action.t(),
      default: nil,
      doc: """
      The action to be executed when the transition is fired,
      you can utilize it to do side effects,
      and update unbonud variables in the out-going arcs.
      """
  end
end
