defmodule ColouredFlow.DSL.Arc do
  @moduledoc """
  `input/2,3` and `output/2,3` macros. See `ColouredFlow.DSL` for context.

  These macros are valid only inside a `transition do ... end` block.
  """

  alias ColouredFlow.DSL.ExpressionHelper

  alias ColouredFlow.Definition.Arc

  @doc """
  Declare an incoming arc (place → transition). The expression must use the
  `bind/1` keyword to consume tokens. Options: `:label`.

  ## Examples

      input :input, bind({1, x})
      input :input, bind({1, x}), label: "in"

      input :input, label: "in" do
        if x > 0, do: bind({1, x}), else: bind({2, x})
      end
  """
  defmacro input(place, expression_or_opts, opts_or_block \\ []) do
    build_arc(place, expression_or_opts, opts_or_block, :p_to_t, "input", __CALLER__)
  end

  @doc """
  Declare an outgoing arc (transition → place). The expression evaluates to the
  multiset of tokens produced. Options: `:label`.

  ## Examples

      output :output, {1, x}
      output :output, {1, x}, label: "out"

      output :output, label: "out" do
        if x > 0, do: {1, x}, else: {0, x}
      end
  """
  defmacro output(place, expression_or_opts, opts_or_block \\ []) do
    build_arc(place, expression_or_opts, opts_or_block, :t_to_p, "output", __CALLER__)
  end

  @spec build_arc(
          Macro.t(),
          Macro.t(),
          Macro.t(),
          Arc.orientation(),
          String.t(),
          Macro.Env.t()
        ) :: Macro.t()
  defp build_arc(place, arg2, arg3, orientation, label, caller) do
    place_value = unquote_atom!(place, "#{label} place", caller)
    {opts, expr_ast} = decompose_args(arg2, arg3, label, caller)

    arc_label = Keyword.get(opts, :label)
    expression = ExpressionHelper.build_arc_expression!(orientation, expr_ast)

    quote do
      ColouredFlow.DSL.Transition.__push_arc__(
        __MODULE__,
        %Arc{
          label: unquote(arc_label),
          orientation: unquote(orientation),
          transition: nil,
          place: unquote(Atom.to_string(place_value)),
          expression: unquote(Macro.escape(expression))
        },
        unquote(caller.file),
        unquote(caller.line)
      )
    end
  end

  # Decompose arc args into {opts_keyword, expression_ast}.
  #
  # Supported forms:
  #   - (place, expression)                          -- arg3 == []
  #   - (place, expression, opts_keyword)            -- arg3 is keyword (no :do)
  #   - (place, opts_keyword, do: expression)        -- arg2 is keyword, arg3 has :do
  #   - (place, do: expression)                      -- arg2 is keyword with :do, arg3 == []
  @spec decompose_args(Macro.t(), Macro.t(), String.t(), Macro.Env.t()) :: {keyword(), Macro.t()}
  defp decompose_args(arg2, arg3, label, caller)

  defp decompose_args(arg2, [], _label, _caller) do
    if keyword?(arg2) and Keyword.has_key?(arg2, :do) do
      {body, opts} = Keyword.pop!(arg2, :do)
      {opts, body}
    else
      {[], arg2}
    end
  end

  defp decompose_args(arg2, arg3, label, caller) when is_list(arg3) do
    cond do
      Keyword.has_key?(arg3, :do) and keyword?(arg2) ->
        {body, opts_after_do} = Keyword.pop!(arg3, :do)
        {arg2 ++ opts_after_do, body}

      Keyword.has_key?(arg3, :do) ->
        {body, _opts} = Keyword.pop!(arg3, :do)
        {[], body}

      keyword?(arg3) ->
        {arg3, arg2}

      true ->
        raise CompileError,
          description: "Invalid `#{label}` arguments: #{inspect(arg3)}",
          file: caller.file,
          line: caller.line
    end
  end

  defp decompose_args(arg2, arg3, label, caller) do
    raise CompileError,
      description: "Invalid `#{label}` arguments: arg2=#{inspect(arg2)}, arg3=#{inspect(arg3)}",
      file: caller.file,
      line: caller.line
  end

  defp keyword?(list) when is_list(list) do
    list != [] and
      Enum.all?(list, fn
        {key, _value} when is_atom(key) -> true
        _other -> false
      end)
  end

  defp keyword?(_other), do: false

  @spec unquote_atom!(Macro.t(), String.t(), Macro.Env.t()) :: atom()
  defp unquote_atom!(value, _label, _caller) when is_atom(value), do: value

  defp unquote_atom!(value, label, caller) do
    raise CompileError,
      description: "Expected #{label} to be an atom, got: #{Macro.to_string(value)}",
      file: caller.file,
      line: caller.line
  end
end
