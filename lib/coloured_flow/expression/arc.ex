defmodule ColouredFlow.Expression.Arc do
  @moduledoc """
  The arc expression utility module.
  """

  alias ColouredFlow.Definition.Variable

  @binding_literal_tag :cpn_bind_literal
  @binding_variable_tag :cpn_bind_variable

  @type value_pattern() :: Macro.t()
  @type binding() :: {
          coefficient ::
            {:cpn_bind_literal, non_neg_integer()}
            | {:cpn_bind_variable, {Variable.name(), meta :: Keyword.t()}},
          value_pattern()
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
      {{:cpn_bind_literal, 1}, {:x, [], __MODULE__}}

      iex> extract_binding(quote do: {x, y})
      {{:cpn_bind_variable, {:x, []}}, {:y, [], __MODULE__}}

      iex> extract_binding(quote do: {x, y when y > 0})
      {{:cpn_bind_variable, {:x, []}}, {:when, [], [{:y, [], __MODULE__}, {:>, [context: __MODULE__, imports: [{2, Kernel}]], [{:y, [], __MODULE__}, 0]}]}}
  """
  @spec extract_binding(Macro.t()) :: binding()
  def extract_binding({coefficient, value}) do
    coefficient = extract_coeefficient(coefficient)
    value = validate_value_pattern(value)

    {coefficient, value}
  end

  def extract_binding(declaration) do
    raise ArgumentError, """
    Invalid declaration for binding, expected a tuple of size 2, got: #{inspect(declaration)}
    """
  end

  defp extract_coeefficient(quoted) do
    cond do
      Macro.quoted_literal?(quoted) ->
        case extract_literal(quoted) do
          coefficient when is_integer(coefficient) and coefficient >= 0 ->
            {@binding_literal_tag, coefficient}

          value ->
            raise ArgumentError, """
            Invalid coefficient for binding, expected a non-negative integer, got: #{inspect(value)}
            """
        end

      var?(quoted) ->
        {@binding_variable_tag, extract_var(quoted)}

      true ->
        raise ArgumentError, """
        Invalid coefficient for binding, expected a non-negative integer or a variable, got: #{inspect(quoted)}
        """
    end
  end

  defp validate_value_pattern(quoted) do
    {_result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          quoted =
            ColouredFlow.EnabledBindingElements.Binding.build_match_expr(
              quoted,
              nil,
              nil
            )

          env = __ENV__
          :elixir_expand.expand(quoted, :elixir_env.env_to_ex(env), env)
        rescue
          _error ->
            :ok
        end
      end)

    if Enum.empty?(diagnostics) do
      quoted
    else
      raise ArgumentError, """
      Invalid value pattern for binding, got: #{inspect(quoted)}

      Diagnostics:

      #{Enum.map_join(diagnostics, "\n", &Map.get(&1, :message))}
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

      iex> get_var_names({{:cpn_bind_literal, 1}, quote do: x})
      [{:x, []}]

      iex> get_var_names({{:cpn_bind_variable, {:x, []}}, quote do: y})
      [{:x, []}, {:y, []}]

      iex> get_var_names({{:cpn_bind_variable, {:x, []}}, quote do: {y, z}})
      [{:x, []}, {:y, []}, {:z, []}]
  """
  @spec get_var_names(binding()) :: [{Variable.name(), meta :: Keyword.t()}]
  def get_var_names({coefficient, value_pattern}) do
    get_var_names_from_coeefficient(coefficient) ++
      get_var_names_from_value_pattern(value_pattern)
  end

  defp get_var_names_from_coeefficient({@binding_variable_tag, var_name}), do: [var_name]
  defp get_var_names_from_coeefficient({@binding_literal_tag, _value}), do: []

  defp get_var_names_from_value_pattern(pattern) do
    pattern
    |> Macro.prewalk([], fn
      {name, meta, context} = ast, acc when is_atom(name) and is_atom(context) ->
        {ast, [{name, meta} | acc]}

      ast, acc ->
        {ast, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end
end
