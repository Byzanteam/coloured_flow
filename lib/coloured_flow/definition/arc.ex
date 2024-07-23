defmodule ColouredFlow.Definition.Arc do
  @moduledoc """
  An arc is a directed connection between a transition and a place.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Expression

  @type name() :: binary()

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :name, name()

    field :orientation, :t_to_p | :p_to_t,
      doc: """
      The orientation of the arc, whether it is from a transition to a place,
      or from a place to a transition.

      - `:t_to_p`: from a transition to a place
      - `:p_to_t`: from a place to a transition
      """

    field :expression, Expression.t(),
      doc: """
      The expression that is used to evaluate the arc.

      When a transition is fired, the tokens in the in-going places are matched
      with the in-going arcs will be consumed, and the tokens in the out-going places
      are updated with the out-going arcs.

      Note that the in-going arcs can't refer to an unbound variable,
      howerver, the out-going arcs can refer to an unbound variable that has to be
      updated by the action of the transition.
      """
  end
end
