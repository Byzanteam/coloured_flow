defmodule ColouredFlow.Expression.Returning do
  @moduledoc """
  The expression returning value, it's used to define the returning value of an expression.
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Variable

  @returning_tag :cpn_returning_variable

  @typep returning() :: {
           coefficient ::
             non_neg_integer() | {:cpn_returning_variable, {Variable.name(), meta :: Keyword.t()}},
           value ::
             {:cpn_returning_variable, {Variable.name(), meta :: Keyword.t()}} | ColourSet.value()
         }

  @doc """
  A macro that return the value as is, this macro is used to mark the returning value.

  ```elixir
  return {1, x}
  # is equal to the below when evaluated
  {1, x}
  ```
  """
  defmacro return(returning) do
    quote do
      unquote(returning)
    end
  end

  @doc """
  Extracts the returning from a quoted expression.

  ## Examples

      iex> extract_returning(quote do: {1, x})
      {1, {:cpn_returning_variable, {:x, []}}}

      iex> extract_returning(quote do: {x, y})
      {{:cpn_returning_variable, {:x, []}}, {:cpn_returning_variable, {:y, []}}}
  """
  @spec extract_returning(Macro.t()) :: returning()
  def extract_returning({coefficient, value}) do
    coefficient = extract_coeefficient(coefficient)
    value = extract_value(value)

    {coefficient, value}
  end

  def extract_returning(declaration) do
    raise """
    Invalid declaration for returning, expected a tuple of size 2, got: #{inspect(declaration)}
    """
  end

  defp extract_coeefficient(quoted) do
    cond do
      Macro.quoted_literal?(quoted) ->
        case extract_literal(quoted) do
          coefficient when is_integer(coefficient) and coefficient >= 0 ->
            coefficient

          value ->
            raise """
            Invalid coefficient for returning, expected a non-negative integer, got: #{inspect(value)}
            """
        end

      var?(quoted) ->
        {@returning_tag, extract_var(quoted)}

      true ->
        raise """
        Invalid coefficient for returning, expected a non-negative integer or a variable, got: #{inspect(quoted)}
        """
    end
  end

  defp extract_value(quoted) do
    cond do
      Macro.quoted_literal?(quoted) ->
        extract_literal(quoted)

      var?(quoted) ->
        {@returning_tag, extract_var(quoted)}

      true ->
        raise """
        Invalid value for returning, expected a variable, got: #{inspect(quoted)}
        """
    end
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

  @doc """
  Get the variable names from the returning value.

  ## Examples

      iex> get_var_names({1, {:cpn_returning_variable, {:x, [line: 1, column: 2]}}})
      [{:x, [line: 1, column: 2]}]

      iex> get_var_names({{:cpn_returning_variable, {:x, []}}, {:cpn_returning_variable, {:y, []}}})
      [{:x, []}, {:y, []}]
  """
  @spec get_var_names(returning()) :: [{Variable.name(), meta :: Keyword.t()}]
  def get_var_names({coefficient, value}) do
    Enum.flat_map([coefficient, value], fn
      {@returning_tag, name_and_meta} -> [name_and_meta]
      _other -> []
    end)
  end

  @doc """
  Prune the meta information from the returning value.

  ## Examples

      iex> prune_meta({1, {:cpn_returning_variable, {:x, [line: 1, column: 2]}}})
      {1, {:cpn_returning_variable, :x}}

      iex> prune_meta({{:cpn_returning_variable, {:x, []}}, {:cpn_returning_variable, {:y, []}}})
      {{:cpn_returning_variable, :x}, {:cpn_returning_variable, :y}}
  """
  @spec prune_meta(returning()) :: ColouredFlow.Definition.Arc.returning()
  def prune_meta({coefficient, value}) do
    coefficient = do_prune_meta(coefficient)
    value = do_prune_meta(value)

    {coefficient, value}
  end

  defp do_prune_meta({@returning_tag, {name, _meta}}), do: {@returning_tag, name}
  defp do_prune_meta(value), do: value
end
