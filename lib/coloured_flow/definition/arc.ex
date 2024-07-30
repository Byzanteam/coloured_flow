defmodule ColouredFlow.Definition.Arc do
  @moduledoc """
  An arc is a directed connection between a transition and a place.
  """

  use TypedStructor

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable

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

    # TODO: move into Expression
    field :returning,
          list({
            non_neg_integer() | {:cpn_variable, Variable.name()},
            {:cpn_variable, Variable.name()} | {:cpn_value, ColourSet.value()}
          }),
          doc: """
          The result that are returned by the arc, is form of a multi-set of tokens.

          - `[{1, {:cpn_variable, :x}}]`: return 1 token of colour `:x`
          - `[{2, {:cpn_variable, :x}}, {3, {:cpn_variable, :y}}]`: return 2 tokens of colour `:x` or 3 tokens of colour `:y`
          - `[{:x, {:cpn_variable, :y}}]`: return `x` tokens of colour `:y`
          - `[{0, {:cpn_variable, :x}}]`: return 0 tokens (empty tokens) of colour `:x`
          """
  end
end
