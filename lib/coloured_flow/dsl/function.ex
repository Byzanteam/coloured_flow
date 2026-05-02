defmodule ColouredFlow.DSL.Function do
  @moduledoc """
  `function/2` and `function/3` macros. See `ColouredFlow.DSL` for context.
  """

  alias ColouredFlow.DSL.ExpressionHelper

  alias ColouredFlow.Definition.Procedure

  @doc """
  Declare a user-defined function (CPN procedure) usable in arc, guard, action,
  and termination expressions. The arguments listed in the head must appear as
  free variables in the body. The return type after `::` is the result colour set.

  ## Examples

      function is_even(x) :: bool(), do: Integer.mod(x, 2) === 0

      function double(x) :: int() do
        x * 2
      end
  """
  defmacro function(head_with_type, body \\ nil) do
    {name, args, result} = decompose_head(head_with_type)
    expr_ast = ExpressionHelper.block_to_ast(body)
    expression = ExpressionHelper.build_from_ast!(expr_ast)

    free_set = MapSet.new(expression.vars)
    declared = MapSet.new(args)

    missing = declared |> MapSet.difference(free_set) |> MapSet.to_list() |> Enum.sort()
    extra = free_set |> MapSet.difference(declared) |> MapSet.to_list() |> Enum.sort()

    {missing_ast, extra_ast, args_ast, name_ast} =
      {Macro.escape(missing), Macro.escape(extra), Macro.escape(args), Macro.escape(name)}

    quote do
      ColouredFlow.DSL.Function.__validate_args__!(
        unquote(name_ast),
        unquote(args_ast),
        unquote(missing_ast),
        unquote(extra_ast)
      )

      @cf_functions %Procedure{
        name: unquote(name),
        expression: unquote(Macro.escape(expression)),
        result: unquote(Macro.escape(result))
      }
    end
  end

  @doc false
  @spec __validate_args__!(atom(), [atom()], [atom()], [atom()]) :: :ok
  def __validate_args__!(name, args, missing, _extra) do
    if missing != [] do
      raise CompileError,
        description: """
        Function `#{name}/#{length(args)}` declares argument(s) \
        #{inspect(missing)}, but they are not referenced in the body.
        """
    end

    # Extra free variables are allowed (other vars/constants resolved at the
    # workflow level), so we don't reject them here.
    :ok
  end

  @spec decompose_head(Macro.t()) :: {atom(), [atom()], ColouredFlow.Definition.ColourSet.descr()}
  defp decompose_head({:"::", _meta, [head, type_ast]}) do
    {name, args} = decompose_call(head)
    type_descr = decompose_type(type_ast)
    {name, args, type_descr}
  end

  defp decompose_head(other) do
    raise ArgumentError, """
    Invalid function head, expected `name(arg1, arg2) :: type()`,
    got: #{Macro.to_string(other)}
    """
  end

  defp decompose_call({name, _meta, args}) when is_atom(name) and is_list(args) do
    arg_names =
      Enum.map(args, fn
        {arg, _meta, ctx} when is_atom(arg) and is_atom(ctx) ->
          arg

        other ->
          raise ArgumentError,
                "function argument must be a variable, got: #{Macro.to_string(other)}"
      end)

    {name, arg_names}
  end

  defp decompose_call({name, _meta, ctx}) when is_atom(name) and is_atom(ctx) do
    {name, []}
  end

  # Reuse Notation.Colset's type decomposer through a public-ish path. Falls
  # back to a small local impl for the cases we need.
  @spec decompose_type(Macro.t()) :: ColouredFlow.Definition.ColourSet.descr()
  defp decompose_type({:{}, _meta, []}), do: {:unit, []}

  defp decompose_type({type1, type2}) do
    {:tuple, [decompose_type(type1), decompose_type(type2)]}
  end

  defp decompose_type({:{}, _meta, types}) do
    {:tuple, Enum.map(types, &decompose_type/1)}
  end

  defp decompose_type({:%{}, _meta, fields}) do
    map = Map.new(fields, fn {key, type} -> {key, decompose_type(type)} end)
    {:map, map}
  end

  defp decompose_type({:list, _meta, [type]}) do
    {:list, decompose_type(type)}
  end

  defp decompose_type(type) do
    case Macro.decompose_call(type) do
      {name, []} when is_atom(name) -> {name, []}
      _other -> raise ArgumentError, "Invalid function return type: #{Macro.to_string(type)}"
    end
  end
end
