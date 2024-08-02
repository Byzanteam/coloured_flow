defmodule ColouredFlow.Definition.Arc do
  @moduledoc """
  An arc is a directed connection between a transition and a place.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition

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

    field :transition, Transition.name()
    field :place, Place.name()

    field :expression, Expression.t(),
      doc: """
      The expression that is used to evaluate the arc.

      When a transition is fired, the tokens in the in-coming places are matched
      with the in-coming arcs will be consumed, and the tokens in the out-going places
      are updated with the out-going arcs.

      Note that incoming arcs cannot refer to an unbound variable,
      but they can refer to variables bound by other incoming arcs
      (see <https://cpntools.org/2018/01/09/resource-allocation-example/>).
      However, outgoing arcs are allowed to refer to an unbound variable
      that will be updated during the transition action.
      """
  end
end
