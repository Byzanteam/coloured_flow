defmodule ColouredFlow.Definition.Action do
  @moduledoc """
  An action is a sequence of code segments that are executed
  when a transition is fired.

  ref: <https://cpntools.org/2018/01/09/code-segments/>
  """

  use TypedStructor

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Variable

  @type output() :: {:cpn_output_variable, Variable.name()} | ColourSet.value()

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :inputs, [Variable.name()],
      doc: """
      The available variables includes the variables in the in-coming places,
      and the constants. The variables in the out-going isn't available.
      """

    field :outputs, [output()],
      doc: """
      The variables are the unbound variables in the out-going places.
      """

    field :code, Expression.t()
  end
end
