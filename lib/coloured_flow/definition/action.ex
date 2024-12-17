defmodule ColouredFlow.Definition.Action do
  @moduledoc """
  An action is an executable program that is executed when a transition is fired.
  It's the workitem handler's responsibility to interpret the payload
  and update the variables in the outputs.

  ref: <https://cpntools.org/2018/01/09/code-segments/>
  """

  use TypedStructor

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

      [quotient: quotient, modulo: modulo]
      ```

      ```typescript
      // typescript code
      const quotient = Math.floor(dividend / divisor);
      const modulo = dividend % divisor;

      return {quotient, modulo};
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

    field :outputs, [Variable.name()],
      default: [],
      doc: """
      The CPNet variables listed in outputs must be **free variables**,
      that are not bound by the incoming arcs, but are bound by the outgoing arcs.

      You can use `ColouredFlow.Builder.SetActionOutputs` phase to set the `outputs`.
      """
  end
end
