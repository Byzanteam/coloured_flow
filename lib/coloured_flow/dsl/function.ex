defmodule ColouredFlow.DSL.Function do
  @moduledoc """
  `function/1` and `function/2` macros. See `ColouredFlow.DSL` for context.
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
    caller_file = __CALLER__.file
    caller_line = __CALLER__.line
    {name, args, result} = decompose_head(head_with_type, __CALLER__)
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
        unquote(extra_ast),
        unquote(caller_file),
        unquote(caller_line)
      )

      @cf_functions %Procedure{
        name: unquote(name),
        expression: unquote(Macro.escape(expression)),
        result: unquote(Macro.escape(result))
      }
      @cf_functions_meta {unquote(name), unquote(caller_file), unquote(caller_line)}
    end
  end

  @doc false
  @spec __validate_args__!(atom(), [atom()], [atom()], [atom()], String.t(), non_neg_integer()) ::
          :ok
  def __validate_args__!(name, args, missing, _extra, file, line) do
    if missing != [] do
      raise CompileError,
        description: """
        Function `#{name}/#{length(args)}` declares argument(s) \
        #{inspect(missing)}, but they are not referenced in the body.
        """,
        file: file,
        line: line
    end

    # Extra free variables are allowed (other vars/constants resolved at the
    # workflow level), so we don't reject them here.
    :ok
  end

  @spec decompose_head(Macro.t(), Macro.Env.t()) ::
          {atom(), [atom()], ColouredFlow.Definition.ColourSet.descr()}
  defp decompose_head({:"::", _meta, [head, type_ast]}, caller) do
    {name, args} = decompose_call(head, caller)
    type_descr = ColouredFlow.Notation.Colset.__decompose_type__(type_ast)
    {name, args, type_descr}
  end

  defp decompose_head(other, caller) do
    raise CompileError,
      description: """
      Invalid function head, expected `name(arg1, arg2) :: type()`,
      got: #{Macro.to_string(other)}
      """,
      file: caller.file,
      line: caller.line
  end

  defp decompose_call({name, _meta, args}, caller) when is_atom(name) and is_list(args) do
    arg_names =
      Enum.map(args, fn
        {arg, _meta, ctx} when is_atom(arg) and is_atom(ctx) ->
          arg

        other ->
          raise CompileError,
            description: "function argument must be a variable, got: #{Macro.to_string(other)}",
            file: caller.file,
            line: caller.line
      end)

    {name, arg_names}
  end

  defp decompose_call({name, _meta, ctx}, _caller) when is_atom(name) and is_atom(ctx) do
    {name, []}
  end
end
