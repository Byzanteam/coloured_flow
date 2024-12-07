defmodule ColouredFlow.Expression.Arc do
  @moduledoc """
  The arc expression utility module.
  """

  @typedoc """
  The bind expression.

  Examples:

      {1, x}
      {x, y}
      {x, y} when y > 0
      {x, [y | rest]} when x > y and length(rest) === 1
  """
  @type bind_expr() :: Macro.t()

  @doc """
  A macro that returns the value as is,
  this macro is used to mark the binding value.

  ```elixir
  bind {1, x}
  # is equal to the below when evaluated
  {1, x}
  ```

  ```elixir
  bind {x, [y | rest]} when x > y and length(rest) === 1
  # is equal to the below when evaluated
  case {x, [y | rest]} do
    {var!(coefficient, __MODULE__), var!(value, __MODULE__)} when x > y and length(rest) === 1 ->
      {:ok, {var!(coefficient, __MODULE__), var!(value, __MODULE__)}}

    _ ->
      :error
  end
  ```
  """
  defmacro bind({coefficient, value}) do
    quote do
      {:ok, {unquote(coefficient), unquote(value)}}
    end
  end

  defmacro bind({:when, meta, [{coefficient, value}, guard]}) do
    coefficient_var = Macro.var(:coefficient, __MODULE__)
    value_var = Macro.var(:value, __MODULE__)
    clause = {:when, meta, [{coefficient_var, value_var}, guard]}

    quote generated: true do
      case {unquote(coefficient), unquote(value)} do
        unquote(clause) -> {:ok, {unquote(coefficient_var), unquote(value)}}
        _other -> :error
      end
    end
  end

  defmacro bind(expr) do
    raise ArgumentError, invalid_bind_expr(expr)
  end

  @spec validate_bind_expr(bind_expr()) :: :ok | {:error, String.t()}
  def validate_bind_expr({coefficient, _value} = expr) do
    with :ok <- validate_coefficient(coefficient) do
      validate_expression(expr)
    end
  end

  def validate_bind_expr({:when, _meta, [{coefficient, _value}, _guard]} = expr) do
    with :ok <- validate_coefficient(coefficient) do
      validate_expression(expr)
    end
  end

  def validate_bind_expr(expr) do
    {:error, invalid_bind_expr(expr)}
  end

  defp validate_coefficient(coefficient) do
    if Macro.quoted_literal?(coefficient) do
      if is_integer(coefficient) and coefficient >= 0 do
        :ok
      else
        {:error, "The coefficient must be a non-negative integer, got: #{coefficient}"}
      end
    else
      :ok
    end
  end

  defp validate_expression(expr) do
    alias ColouredFlow.EnabledBindingElements.Binding

    {_result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          quoted = Binding.build_match_expr(expr)

          env = __ENV__
          :elixir_expand.expand(quoted, :elixir_env.env_to_ex(env), env)
        rescue
          _error ->
            :ok
        end
      end)

    if Enum.empty?(diagnostics) do
      :ok
    else
      {
        :error,
        """
        Invalid bind expression, got: #{inspect(expr)}

        Diagnostics:

        #{Enum.map_join(diagnostics, "\n", &Map.get(&1, :message))}
        """
      }
    end
  end

  defp invalid_bind_expr(expr) do
    """
    Invalid bind expression, expected in the form of `{coefficient, value}`, or `{coefficient, value} guard`,
    but got: #{inspect(Macro.to_string(expr))}
    """
  end

  @spec extract_bind_exprs(Macro.t()) :: [bind_expr()]
  def extract_bind_exprs(quoted) do
    quoted
    |> Macro.prewalk([], fn
      {:bind, _meta, [bind_expr]} = ast, acc -> {ast, [bind_expr | acc]}
      ast, acc -> {ast, acc}
    end)
    |> elem(1)
  end
end
