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
  alias ColouredFlow.Expression.Action, as: ActionExpression

  # TODO: meta is necessary?
  @type output() ::
          {:cpn_output_variable, {Variable.name(), meta :: keyword()}} | ColourSet.value()

  typed_structor do
    plugin TypedStructor.Plugins.DocFields

    field :code, Expression.t(),
      doc: """
      The code segment to be executed when the transition is fired.

      Examples:

      ```
      quotient = div(dividend, divisor)
      modulo = Integer.mod(dividend, divisor)

      # use `output` keyword to mark outputs
      output {quotient, modulo}

      # the outputs are:
      [
        [
          cpn_output_variable: {:quotient, [line: 4, column: 9]},
          cpn_output_variable: {:modulo, [line: 4, column: 19]}
        ]
      ]

      ```

      ```
      output {1, x}

      # the outpus are:
      [
        [
          1,
          {:cpn_output_variable, {:x, [line: 1, column: 12]}}
        ]
      ]
      ```
      """

    field :outputs, [[output()]],
      enforce: true,
      doc: """
      The return values of the action will be bound to the free variables.

      - `[1, {:cpn_output_variable, :x}]`: outputs [1, x]
      - `[{:cpn_output_variable, :x}, {:cpn_output_variable, :x}]`: outputs [x, x]
      """
  end

  @spec build_outputs(Expression.t()) ::
          {:ok, list(list(output()))} | {:error, ColouredFlow.Expression.compile_error()}
  def build_outputs(%Expression{} = expression) do
    outputs = extract_outputs(expression.expr)
    check_outputs(outputs)
  end

  @spec build_outputs!(Expression.t()) :: list(list(output()))
  def build_outputs!(%Expression{} = expression) do
    case build_outputs(expression) do
      {:ok, outputs} -> outputs
      {:error, reason} -> raise inspect(reason)
    end
  end

  defp extract_outputs(quoted) do
    quoted
    |> Macro.prewalk([], fn
      {:output, _meta, [result]} = ast, acc ->
        {ast, [ActionExpression.extract_output(result) | acc]}

      ast, acc ->
        {ast, acc}
    end)
    |> elem(1)
  end

  defp check_outputs([]), do: {:ok, []}
  defp check_outputs([output]), do: {:ok, [output]}

  defp check_outputs(outputs) do
    # OPTIMIZE: check output types at the corresponding position
    outputs
    |> Enum.group_by(&Enum.count/1)
    |> map_size()
    |> case do
      1 -> {:ok, outputs}
      _other -> {:error, {[], "All outputs must have the same length", ""}}
    end
  end
end
