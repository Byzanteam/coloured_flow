defmodule ColouredFlow.Expression.Action do
  @moduledoc """
  The action expression of a transition utility module.
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Variable

  @output_tag :cpn_output_variable

  @typep output() ::
           {:cpn_output_variable, {Variable.name(), meta :: Keyword.t()}} | ColourSet.value()

  @doc """
  A macro that return the value as is,
  this macro is used to mark the returning value.

  ```elixir
  output {1, 2, 3}
  # is equal to the below when evaluated
  {1, 2, 3}
  ```
  """
  defmacro output(result) do
    quote do
      unquote(result)
    end
  end

  @doc """
  Extracts the output from a quoted expression.

  ## Examples

      iex> extract_output(quote do: {1, x})
      [1, {:cpn_output_variable, {:x, []}}]

      iex> extract_output(quote do: {x, y})
      [{:cpn_output_variable, {:x, []}}, {:cpn_output_variable, {:y, []}}]
  """
  @spec extract_output(Macro.t()) :: list(output())
  def extract_output({value1, value2}), do: do_extract_output([value1, value2])
  def extract_output({:{}, _meta, args}) when is_list(args), do: do_extract_output(args)

  def extract_output(declaration) do
    raise """
    Invalid declaration for output, expected a tuple, got: #{inspect(declaration)}
    """
  end

  defp do_extract_output(quoted, acc \\ [])

  defp do_extract_output([], acc), do: Enum.reverse(acc)

  defp do_extract_output([quoted | rest], acc) do
    output =
      cond do
        Macro.quoted_literal?(quoted) ->
          extract_literal(quoted)

        var?(quoted) ->
          {@output_tag, extract_var(quoted)}

        true ->
          raise """
          Invalid output, expected a literal value or a variable, got: #{inspect(quoted)}
          """
      end

    do_extract_output(rest, [output | acc])
  end

  defp var?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true
  defp var?(_quoted), do: false

  defp extract_literal(quoted) do
    quoted
    |> Code.eval_quoted()
    |> elem(0)
  end

  defp extract_var({name, meta, context}) when is_atom(name) and is_atom(context),
    do: {name, meta}
end
