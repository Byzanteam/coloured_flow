defmodule ColouredFlow.Expression.Arc do
  @moduledoc """
  The arc expression utility module.
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Variable

  @binding_tag :cpn_bind_variable

  @typep binding() :: {
           coefficient ::
             non_neg_integer() | {:cpn_bind_variable, {Variable.name(), meta :: Keyword.t()}},
           value ::
             {:cpn_bind_variable, {Variable.name(), meta :: Keyword.t()}} | ColourSet.value()
         }

  @doc """
  A macro that returns the value as is,
  this macro is used to mark the binding value.

  ```elixir
  bind {1, x}
  # is equal to the below when evaluated
  {1, x}
  ```
  """
  defmacro bind(binding) do
    quote do
      unquote(binding)
    end
  end

  @doc """
  Extracts the binding from a quoted expression.

  ## Examples

      iex> extract_binding(quote do: {1, x})
      {1, {:cpn_bind_variable, {:x, []}}}

      iex> extract_binding(quote do: {x, y})
      {{:cpn_bind_variable, {:x, []}}, {:cpn_bind_variable, {:y, []}}}
  """
  @spec extract_binding(Macro.t()) :: binding()
  def extract_binding({coefficient, value}) do
    coefficient = extract_coeefficient(coefficient)
    value = extract_value(value)

    {coefficient, value}
  end

  def extract_binding(declaration) do
    raise """
    Invalid declaration for binding, expected a tuple of size 2, got: #{inspect(declaration)}
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
            Invalid coefficient for binding, expected a non-negative integer, got: #{inspect(value)}
            """
        end

      var?(quoted) ->
        {@binding_tag, extract_var(quoted)}

      true ->
        raise """
        Invalid coefficient for binding, expected a non-negative integer or a variable, got: #{inspect(quoted)}
        """
    end
  end

  defp extract_value(quoted) do
    cond do
      Macro.quoted_literal?(quoted) ->
        extract_literal(quoted)

      var?(quoted) ->
        {@binding_tag, extract_var(quoted)}

      true ->
        raise """
        Invalid value for binding, expected a variable, got: #{inspect(quoted)}
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
  Get the variable names from the binding value.

  ## Examples

      iex> get_var_names({1, {:cpn_bind_variable, {:x, [line: 1, column: 2]}}})
      [{:x, [line: 1, column: 2]}]

      iex> get_var_names({{:cpn_bind_variable, {:x, []}}, {:cpn_bind_variable, {:y, []}}})
      [{:x, []}, {:y, []}]
  """
  @spec get_var_names(binding()) :: [{Variable.name(), meta :: Keyword.t()}]
  def get_var_names({coefficient, value}) do
    Enum.flat_map([coefficient, value], fn
      {@binding_tag, name_and_meta} -> [name_and_meta]
      _other -> []
    end)
  end

  @doc """
  Prune the meta information from the binding value.

  ## Examples

      iex> prune_meta({1, {:cpn_bind_variable, {:x, [line: 1, column: 2]}}})
      {1, {:cpn_bind_variable, :x}}

      iex> prune_meta({{:cpn_bind_variable, {:x, []}}, {:cpn_bind_variable, {:y, []}}})
      {{:cpn_bind_variable, :x}, {:cpn_bind_variable, :y}}
  """
  @spec prune_meta(binding()) :: ColouredFlow.Definition.Arc.binding()
  def prune_meta({coefficient, value}) do
    coefficient = do_prune_meta(coefficient)
    value = do_prune_meta(value)

    {coefficient, value}
  end

  defp do_prune_meta({@binding_tag, {name, _meta}}), do: {@binding_tag, name}
  defp do_prune_meta(value), do: value
end
