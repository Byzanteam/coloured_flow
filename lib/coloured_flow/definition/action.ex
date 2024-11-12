defmodule ColouredFlow.Definition.Action do
  @moduledoc """
  An action is an executable program that is executed when a transition is fired.
  It's the workitem handler's responsibility to interpret the payload
  and update the variables in the outputs.

  ref: <https://cpntools.org/2018/01/09/code-segments/>
  """

  use TypedStructor

  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Variable

  @type payload() :: binary()

  typed_structor do
    plugin TypedStructor.Plugins.DocFields

    field :payload, payload(),
      doc: """
      The payload is passed to the workitem handler to execute,
      it can be a code snippet in any language, a JSON object, or a binary,
      as long as the workitem handler can interpret it.

      Examples:

      ```
      # elixir code
      quotient = div(dividend, divisor)
      modulo = Integer.mod(dividend, divisor)

      {quotient, modulo}
      ```

      ```typescript
      // typescript code
      const quotient = Math.floor(dividend / divisor);
      const modulo = dividend % divisor;

      return [quotient, modulo];
      ```

      ```json
      {
        "jsonrpc": "2.0",
        "method": "division",
        "params": ["$dividend", "$divisor"],
        "id": 1
      }
      ```
      """

    field :inputs, [Variable.name() | Constant.name()],
      doc: """
      The CPNet variables or constants listed in inputs can be used in the code expression.
      The variables will be bound and passed to the action when the transition is fired.
      If `nil` is specified, all the variables and constants in the current scope are allowed to be used.

      Examples:

      ```elixir
      [:dividend, :divisor]
      ```
      """

    field :outputs, [Variable.name()],
      default: [],
      doc: """
      The CPNet variables listed in outputs must be **free variables**,
      that are not bound by the incoming arcs, but are bound by the outgoing arcs.
      """
  end
end
