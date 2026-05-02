defmodule ColouredFlow.DSL.ExpressionHelper do
  @moduledoc """
  Helpers that convert an Elixir AST captured by a DSL macro into a
  `ColouredFlow.Definition.Expression`.

  See `ColouredFlow.DSL` for the full DSL spec.
  """

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.Expression

  @doc """
  Build an `Expression` from an Elixir AST.

  Stringifies the AST to populate `Expression.code` and reuses
  `ColouredFlow.Definition.Expression.build/1` to extract free variables.

  ## Examples

      iex> ast = quote do: x + 1
      iex> %ColouredFlow.Definition.Expression{vars: [:x]} =
      ...>   ColouredFlow.DSL.ExpressionHelper.build_from_ast!(ast)
  """
  @spec build_from_ast!(Macro.t()) :: Expression.t()
  def build_from_ast!(ast) do
    case build_from_ast(ast) do
      {:ok, expr} -> expr
      {:error, reason} -> raise "failed to build expression: #{inspect(reason)}"
    end
  end

  @doc """
  Build an `Expression` from an Elixir AST. Returns `{:ok, expression}` or
  `{:error, reason}`.
  """
  @spec build_from_ast(Macro.t()) ::
          {:ok, Expression.t()} | {:error, ColouredFlow.Expression.compile_error()}
  def build_from_ast(nil) do
    {:ok, %Expression{}}
  end

  def build_from_ast(ast) do
    code = ast_to_code(ast)
    Expression.build(code)
  end

  @doc """
  Build an arc `Expression` for the given orientation from an Elixir AST.

  Equivalent to `ColouredFlow.Definition.Arc.build_expression/2` plus AST
  stringification.

  ## Examples

      iex> ast = quote do: bind({1, x})
      iex> %ColouredFlow.Definition.Expression{vars: [:x]} =
      ...>   ColouredFlow.DSL.ExpressionHelper.build_arc_expression!(:p_to_t, ast)
  """
  @spec build_arc_expression!(Arc.orientation(), Macro.t()) :: Expression.t()
  def build_arc_expression!(orientation, ast)
      when orientation in [:p_to_t, :t_to_p] do
    code = ast_to_code(ast)

    case Arc.build_expression(orientation, code) do
      {:ok, expr} -> expr
      {:error, reason} -> raise "failed to build arc expression: #{inspect(reason)}"
    end
  end

  @doc """
  Returns a sorted list of free atom-vars referenced in the AST.

  Free vars are determined by `ColouredFlow.Expression.compile/2` (so this is
  consistent with how the rest of the engine extracts variables).

  ## Examples

      iex> ColouredFlow.DSL.ExpressionHelper.free_vars(quote do: x + y)
      [:x, :y]

      iex> ColouredFlow.DSL.ExpressionHelper.free_vars(quote do: 1 + 2)
      []
  """
  @spec free_vars(Macro.t()) :: [atom()]
  def free_vars(ast) do
    case build_from_ast(ast) do
      {:ok, %Expression{vars: vars}} -> vars
      {:error, reason} -> raise "failed to compile expression: #{inspect(reason)}"
    end
  end

  @doc """
  Convert a `do` block to a single AST node.

  When a `do ... end` block contains a single statement Elixir keeps the AST
  as-is; multiple statements are wrapped in an `:__block__`.

  ## Examples

      iex> ColouredFlow.DSL.ExpressionHelper.block_to_ast(do: 1 + 1)
      quote(do: 1 + 1)
  """
  @spec block_to_ast(Macro.t()) :: Macro.t() | nil
  def block_to_ast(nil), do: nil

  def block_to_ast(do: block), do: block

  def block_to_ast(block) when is_list(block) do
    case Keyword.fetch(block, :do) do
      {:ok, body} -> body
      :error -> raise ArgumentError, "expected a `do ... end` block, got: #{inspect(block)}"
    end
  end

  def block_to_ast(other), do: other

  @doc """
  Convert an AST back to a code string suitable for `Expression.build/1`.
  """
  @spec ast_to_code(Macro.t()) :: binary()
  def ast_to_code(ast) when is_nil(ast), do: ""
  def ast_to_code(ast), do: Macro.to_string(ast)
end
