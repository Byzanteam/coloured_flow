defmodule ColouredFlow.Expression do
  @moduledoc """
  An Elixir expression.
  """

  alias ColouredFlow.Expression.Env
  alias ColouredFlow.Expression.EvalDiagnostic
  alias ColouredFlow.Expression.Scope

  @doc """
  Converts a string to a quoted expression and returns its ast and the unbound variables.

  ## Examples

      iex> {:ok, _quoted, unbound_vars} = compile("a + b")
      iex> %{a: [[line: 1, column: 1]], b: [[line: 1, column: 5]]} = unbound_vars

      iex> {:ok, _quoted, unbound_vars} = compile(\"""
      ...> fun = fn a -> a + b end
      ...> fun.(a)
      ...> \""")
      iex> %{a: [[line: 2, column: 6]], b: [[line: 1, column: 19]]} =  unbound_vars
  """

  @typedoc """
  The error that is returned when the string can't be converted to a quoted expression.

  ## Examples

      iex> {:error, _reason} = compile("a + b +")
      {:error, {[line: 1, column: 7], "syntax error before: ", ""}}
  """
  @type compile_error() ::
          {
            meta :: keyword(),
            message_info :: binary() | {binary(), binary()},
            token :: binary()
          }

  @spec compile(string :: binary(), env :: Macro.Env.t()) ::
          {:ok, Macro.t(), Scope.vars()}
          | {:error, compile_error()}
  def compile(string, env \\ __ENV__) when is_binary(string) do
    with({:ok, quoted} <- Code.string_to_quoted(string, columns: true)) do
      scope = analyse_node(quoted, Scope.new(env))

      {:ok, quoted, Scope.merge_vars(scope.free_vars, scope.pinned_vars)}
    end
  end

  @spec analyse_node(Macro.t(), Scope.t()) :: Scope.t()
  defp analyse_node(quoted, scope)

  # {form, meta, args} when is_atom(form)
  defp analyse_node({name, meta, context}, scope) when is_atom(name) and is_atom(context) do
    if Scope.has_var?(scope.bound_vars, name) do
      scope
    else
      %Scope{
        scope
        | free_vars: Scope.put_var(scope.free_vars, name, meta)
      }
    end
  end

  defp analyse_node({:"::", _meta, [left, _right]}, scope) do
    analyse_node(left, scope)
  end

  defp analyse_node({:^, _meta, args}, scope) do
    pin_scope = analyse_node(args, Scope.new(scope))

    pinned_vars =
      pin_scope.free_vars
      |> Scope.merge_vars(pin_scope.pinned_vars)
      |> Scope.drop_vars(scope.bound_vars)

    %Scope{scope | pinned_vars: pinned_vars}
  end

  defp analyse_node({op, _meta, [left, right]}, scope) when op in [:=, :<-] do
    left_analysis = analyse_node(left, Scope.new(scope, bound_vars: scope.bound_vars))
    right_analysis = analyse_node(right, scope)

    %Scope{
      scope
      | bound_vars: Scope.merge_vars(scope.bound_vars, left_analysis.free_vars),
        free_vars: Scope.merge_vars(scope.free_vars, right_analysis.free_vars),
        pinned_vars: Scope.merge_vars(left_analysis.pinned_vars, right_analysis.pinned_vars)
    }
  end

  defp analyse_node({:->, _meta, [[{:when, _when_meta, when_args}], body]}, scope) do
    {args, when_args} = split_last(when_args)

    args_analysis = analyse_node(args, Scope.new(scope, bound_vars: scope.bound_vars))
    bound_vars = Scope.merge_vars(scope.bound_vars, args_analysis.free_vars)

    new_scope = Scope.new(scope, bound_vars: bound_vars)
    when_args_analysis = analyse_node(when_args, new_scope)
    final_analysis = analyse_node(body, when_args_analysis)

    %Scope{
      scope
      | free_vars: Scope.merge_vars(scope.free_vars, final_analysis.free_vars),
        pinned_vars: Scope.merge_vars(args_analysis.pinned_vars, final_analysis.pinned_vars)
    }
  end

  defp analyse_node({:->, _meta, [args, body]}, scope) do
    args_analysis = analyse_node(args, Scope.new(scope, bound_vars: scope.bound_vars))
    bound_vars = Scope.merge_vars(scope.bound_vars, args_analysis.free_vars)
    body_analysis = analyse_node(body, Scope.new(scope, bound_vars: bound_vars))

    %Scope{
      scope
      | free_vars: Scope.merge_vars(scope.free_vars, body_analysis.free_vars),
        pinned_vars: Scope.merge_vars(args_analysis.pinned_vars, body_analysis.pinned_vars)
    }
  end

  defp analyse_node({:__block__, _meta, blocks}, scope) when is_list(blocks) do
    Enum.reduce(blocks, scope, &analyse_node/2)
  end

  defp analyse_node({op, _meta, args}, scope) when op in [:fn, :try] do
    new_scope = Scope.new(scope, bound_vars: scope.bound_vars)
    new_scope = analyse_node(args, new_scope)

    %Scope{
      scope
      | free_vars: Scope.merge_vars(scope.free_vars, new_scope.free_vars),
        pinned_vars: Scope.merge_vars(scope.pinned_vars, new_scope.pinned_vars)
    }
  end

  defp analyse_node({op, _meta, args}, scope) when op in [:for, :with] do
    {clauses, blocks} = split_last(args)
    {do_block, blocks} = Keyword.split(blocks, [:do])

    scope_for_do =
      Enum.reduce(clauses, Scope.new(scope, bound_vars: scope.bound_vars), &analyse_node/2)

    do_analysis = analyse_node(do_block, scope_for_do)

    blocks_analysisi =
      Enum.reduce(blocks, scope, fn block, acc ->
        block
        |> analyse_node(scope)
        |> Scope.merge(acc)
      end)

    %Scope{
      scope
      | free_vars:
          scope.free_vars
          |> Scope.merge_vars(do_analysis.free_vars)
          |> Scope.merge_vars(blocks_analysisi.free_vars),
        pinned_vars:
          scope.pinned_vars
          |> Scope.merge_vars(do_analysis.pinned_vars)
          |> Scope.merge_vars(blocks_analysisi.pinned_vars)
    }
  end

  defp analyse_node({form, _meta, args} = ast, scope) when is_atom(form) do
    # expand macros(like `match?/2`, `destructure/2`, etc.)
    case Macro.expand(ast, scope.env) do
      ^ast -> analyse_node(args, scope)
      new_ast -> analyse_node(new_ast, scope)
    end
  end

  # {form, meta, args}
  defp analyse_node({form, _meta, args}, scope) do
    form_analysis = analyse_node(form, scope)
    args_analysis = analyse_node(args, scope)

    Scope.merge(form_analysis, args_analysis)
  end

  # {left, right}
  @new_scope_ops [:do, :else, :after, :catch, :rescue]
  defp analyse_node({op, value}, scope) when op in @new_scope_ops do
    new_scope = Scope.new(scope, bound_vars: scope.bound_vars)
    new_scope = analyse_node(value, new_scope)

    %Scope{
      scope
      | free_vars: Scope.merge_vars(scope.free_vars, new_scope.free_vars),
        pinned_vars: Scope.merge_vars(scope.pinned_vars, new_scope.pinned_vars)
    }
  end

  defp analyse_node({left, right}, scope) do
    analyse_node([left, right], scope)
  end

  # list when is_list(list)
  defp analyse_node(list, scope) when is_list(list) do
    Enum.reduce(list, scope, fn item, acc ->
      item
      |> analyse_node(scope)
      |> Scope.merge(acc)
    end)
  end

  # others
  defp analyse_node(_ast, scope) do
    scope
  end

  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec split_last(list(item)) :: {list(item), item} when item: term()
  defp split_last(args) when is_list(args) do
    {left, [right]} = Enum.split(args, -1)
    {left, right}
  end

  @spec eval(quoted :: Macro.t(), binding :: Code.binding(), env :: Macro.Env.t()) ::
          {:ok, term()} | {:error, [Exception.t()]}
  # credo:disable-for-previous-line JetCredo.Checks.ExplicitAnyType
  def eval(quoted, binding, env \\ Env.make_env()) when is_list(binding) do
    {result, all_errors_and_warnings} =
      Code.with_diagnostics(fn ->
        try do
          {result, _binding, _env} =
            Code.eval_quoted_with_env(quoted, binding, env, prune_binding: true)

          {:ok, result}
        rescue
          error -> {:error, error}
        end
      end)

    merge_diagnostics(result, all_errors_and_warnings)
  end

  defp merge_diagnostics({:ok, result}, _diagnostics), do: {:ok, result}

  # omits the compile error, for the diagnostics include the details
  defp merge_diagnostics({:error, error}, all_errors_and_warnings)
       when is_exception(error, CompileError) do
    {:error, Enum.map(all_errors_and_warnings, &EvalDiagnostic.exception/1)}
  end

  defp merge_diagnostics({:error, error}, all_errors_and_warnings) do
    {:error, [error | Enum.map(all_errors_and_warnings, &EvalDiagnostic.exception/1)]}
  end
end
