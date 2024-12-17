defmodule ColouredFlow.Definition.Transition do
  @moduledoc """
  Transition t is enabled at a binding if there are tokens
  matching the values of the in-coming arc inscriptions and
  the guard of t evaluates to true.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Expression

  @type name() :: binary()

  typed_structor do
    plugin TypedStructor.Plugins.DocFields

    field :name, name(), enforce: true

    field :guard, Expression.t(),
      doc: """
      The guard of the transition.
      If not specified, the transition is always enabled.

      Note that, the guard can't refer to an unbound variable,
      it can only refer to variables from incoming arcs or constants.

      If the guard is `nil`, the transition is always enabled.
      However, if the guard code is `""`, the transition is never enabled.
      See `ColouredFlow.Definition.Expression.build/1` for more details.
      """

    field :action, Action.t(),
      enforce: true,
      doc: """
      The action to be executed when the transition is fired,
      you can utilize it to do side effects,
      and update unbonud variables in the out-going arcs.
      """
  end
end
