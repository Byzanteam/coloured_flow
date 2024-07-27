defmodule ColouredFlow.Expression do
  @moduledoc """
  An Elixir expression.
  """

  alias ColouredFlow.Definition.Variable

  alias ColouredFlow.Expression.Scope

  @doc """
  Converts a string to a quoted expression and returns its ast and the free variables.

  ## Examples

      iex> string_to_quoted("a + b")
      {
        :ok,
        {
          :+,
          [line: 1, column: 3],
          [
            {:a, [line: 1, column: 1], nil},
            {:b, [line: 1, column: 5], nil}
          ]
        },
        MapSet.new([:a, :b])
      }
  """

  @spec string_to_quoted(string :: binary(), env :: Macro.Env.t()) ::
          {:ok, Macro.t(), MapSet.t(Variable.name())}
          | {:error, reason :: term()}
  # credo:disable-for-previous-line JetCredo.Checks.ExplicitAnyType
  def string_to_quoted(string, env \\ __ENV__) when is_binary(string) do
    with({:ok, quoted} <- Code.string_to_quoted(string, columns: true)) do
      scope = analyse_node(quoted, Scope.new(env))

      {:ok, quoted, MapSet.union(scope.free_vars, scope.pinned_vars)}
    end
  end

  @spec analyse_node(Macro.t(), Scope.t()) :: Scope.t()
  defp analyse_node(quoted, scope)

  # {form, meta, args} when is_atom(form)
  defp analyse_node({name, _meta, context}, scope) when is_atom(name) and is_atom(context) do
    if MapSet.member?(scope.bound_vars, name) do
      scope
    else
      %Scope{
        scope
        | free_vars: MapSet.put(scope.free_vars, name)
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
      |> MapSet.union(pin_scope.pinned_vars)
      |> MapSet.difference(scope.bound_vars)

    %{scope | pinned_vars: pinned_vars}
  end

  defp analyse_node({op, _meta, [left, right]}, scope) when op in [:=, :<-] do
    left_analysis = analyse_node(left, Scope.new(scope, bound_vars: scope.bound_vars))
    right_analysis = analyse_node(right, scope)

    %Scope{
      scope
      | bound_vars: MapSet.union(scope.bound_vars, left_analysis.free_vars),
        free_vars: MapSet.union(scope.free_vars, right_analysis.free_vars),
        pinned_vars: MapSet.union(left_analysis.pinned_vars, right_analysis.pinned_vars)
    }
  end

  defp analyse_node({:->, _meta, [[{:when, _when_meta, when_args}], body]}, scope) do
    {args, when_args} = split_last(when_args)

    args_analysis = analyse_node(args, Scope.new(scope, bound_vars: scope.bound_vars))
    bound_vars = MapSet.union(scope.bound_vars, args_analysis.free_vars)

    new_scope = Scope.new(scope, bound_vars: bound_vars)
    when_args_analysis = analyse_node(when_args, new_scope)
    final_analysis = analyse_node(body, when_args_analysis)

    %Scope{
      scope
      | free_vars: MapSet.union(scope.free_vars, final_analysis.free_vars),
        pinned_vars: MapSet.union(args_analysis.pinned_vars, final_analysis.pinned_vars)
    }
  end

  defp analyse_node({:->, _meta, [args, body]}, scope) do
    args_analysis = analyse_node(args, Scope.new(scope, bound_vars: scope.bound_vars))
    bound_vars = MapSet.union(scope.bound_vars, args_analysis.free_vars)
    body_analysis = analyse_node(body, Scope.new(scope, bound_vars: bound_vars))

    %Scope{
      scope
      | free_vars: MapSet.union(scope.free_vars, body_analysis.free_vars),
        pinned_vars: MapSet.union(args_analysis.pinned_vars, body_analysis.pinned_vars)
    }
  end

  defp analyse_node({:__block__, _meta, blocks}, scope) when is_list(blocks) do
    Enum.reduce(blocks, scope, &analyse_node/2)
  end

  defp analyse_node({op, _meta, args}, scope) when op in [:fn, :try] do
    new_scope = Scope.new(scope, bound_vars: scope.bound_vars)
    new_scope = analyse_node(args, new_scope)

    %{
      scope
      | free_vars: MapSet.union(scope.free_vars, new_scope.free_vars),
        pinned_vars: MapSet.union(scope.pinned_vars, new_scope.pinned_vars)
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
          |> MapSet.union(do_analysis.free_vars)
          |> MapSet.union(blocks_analysisi.free_vars),
        pinned_vars:
          scope.pinned_vars
          |> MapSet.union(do_analysis.pinned_vars)
          |> MapSet.union(blocks_analysisi.pinned_vars)
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

    %{
      scope
      | free_vars: MapSet.union(scope.free_vars, new_scope.free_vars),
        pinned_vars: MapSet.union(scope.pinned_vars, new_scope.pinned_vars)
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
end
