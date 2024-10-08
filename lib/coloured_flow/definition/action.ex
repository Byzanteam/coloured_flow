defmodule ColouredFlow.Definition.Action do
  @moduledoc """
  An action is a sequence of code segments that are executed
  when a transition is fired.

  ref: <https://cpntools.org/2018/01/09/code-segments/>
  """

  use TypedStructor

  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Variable

  typed_structor do
    plugin TypedStructor.Plugins.DocFields

    field :code, Expression.t(),
      doc: """
      The code segment to be executed when the transition is fired.

      Examples:

      ```
      quotient = div(dividend, divisor)
      modulo = Integer.mod(dividend, divisor)

      # The outputs are bound to two variables specified in the outputs field
      {quotient, modulo}
      ```

      ```
      # The outputs are empty
      {}
      ```
      """

    field :inputs, [Variable.name() | Constant.name()],
      default: [],
      doc: """
      The CPNet variables or constants listed in inputs can be used in the code expression.
      The variables will be bound and passed to the action when the transition is fired.
      """

    field :outputs, [Variable.name()],
      default: [],
      doc: """
      The CPNet variables listed in outputs must be **free variables**,
      that are not bound by the incoming arcs, but are bound by the outgoing arcs.
      """
  end
end
