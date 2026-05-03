defmodule ColouredFlow.DSL.Transition do
  @moduledoc """
  `transition/2`, `guard/1`, `action/1` macros. See `ColouredFlow.DSL` for
  context.

  Internally this module uses the module attribute `@__cf_transition_scope__` on
  the calling module to track the current open transition while expanding the
  block body. The scope is a map of `%{name, arcs, guard, action}`.
  """

  alias ColouredFlow.DSL.ExpressionHelper

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Transition

  @scope_attr :__cf_transition_scope__

  # Magic bindings made available inside an `action do ... end` body, in
  # addition to any free CPN variables resolved from the transition's binding.
  @action_magic_bindings [:ctx, :workitem, :extras]

  @doc """
  Declare a transition. The block accepts `guard/1`, `action/1`, `input/2,3` and
  `output/2,3`.

  ## Examples

      transition :pass_through do
        guard x > 0

        input :input, bind({1, x})
        output :output, {1, x * 2}

        action do
          :ok
        end
      end
  """
  defmacro transition(name, opts \\ []) do
    caller_file = __CALLER__.file
    caller_line = __CALLER__.line
    name_value = unquote_atom!(name, "transition name", __CALLER__)
    name_str = Atom.to_string(name_value)

    block =
      case opts do
        list when is_list(list) -> Keyword.get(list, :do)
        _other -> nil
      end

    if is_nil(block) do
      raise CompileError,
        description: "transition/2 requires a `do ... end` block, got: #{inspect(opts)}",
        file: caller_file,
        line: caller_line
    end

    quote do
      ColouredFlow.DSL.Transition.__open_transition__!(
        __MODULE__,
        unquote(name_str),
        unquote(caller_file),
        unquote(caller_line)
      )

      unquote(block)

      ColouredFlow.DSL.Transition.__close_transition__!(__MODULE__)

      @cf_transitions_meta {unquote(name_str), unquote(caller_file), unquote(caller_line)}
    end
  end

  @doc """
  Boolean expression over bound variables. Optional. Returning a falsy value
  disables the transition for the current binding.

  ## Examples

      guard x > 0
      guard do
        x > 0 and is_even(x)
      end
  """
  defmacro guard(expression) do
    caller_file = __CALLER__.file
    caller_line = __CALLER__.line
    expr_ast = ExpressionHelper.block_to_ast(expression)
    expr = ExpressionHelper.build_from_ast!(expr_ast)

    quote do
      ColouredFlow.DSL.Transition.__set_guard__!(
        __MODULE__,
        unquote(Macro.escape(expr)),
        unquote(caller_file),
        unquote(caller_line)
      )
    end
  end

  @doc """
  Expression evaluated when the transition fires. Optional. Use for output
  bindings (when an outgoing arc references an unbound variable) and for side
  effects.

  ## Examples

      action :ok
      action do
        log("fired")
        :ok
      end
  """
  defmacro action(expression) do
    caller_file = __CALLER__.file
    caller_line = __CALLER__.line
    expr_ast = ExpressionHelper.block_to_ast(expression)
    code = ExpressionHelper.ast_to_code(expr_ast)

    raw_free = ExpressionHelper.free_vars(expr_ast)
    cpn_vars = raw_free -- @action_magic_bindings
    escaped_ast = Macro.escape(expr_ast)

    quote do
      ColouredFlow.DSL.Transition.__set_action__!(
        __MODULE__,
        %{
          code: unquote(code),
          body: unquote(escaped_ast),
          cpn_vars: unquote(cpn_vars)
        },
        unquote(caller_file),
        unquote(caller_line)
      )
    end
  end

  @doc false
  @spec __open_transition__!(module(), String.t(), String.t(), non_neg_integer()) :: :ok
  def __open_transition__!(module, name, file, line) when is_atom(module) and is_binary(name) do
    if Module.get_attribute(module, @scope_attr) do
      raise CompileError,
        description: "transition/2 cannot be nested",
        file: file,
        line: line
    end

    Module.put_attribute(module, @scope_attr, %{
      name: name,
      arcs: [],
      guard: nil,
      action: nil
    })

    :ok
  end

  @doc false
  @spec __close_transition__!(module()) :: :ok
  def __close_transition__!(module) do
    scope = Module.get_attribute(module, @scope_attr)

    if is_nil(scope) do
      raise CompileError,
        description: "internal error: closing transition that wasn't opened",
        file: source_file(module),
        line: 0
    end

    arcs =
      scope.arcs
      |> Enum.reverse()
      |> Enum.map(fn %Arc{} = arc -> %Arc{arc | transition: scope.name} end)

    transition = %Transition{
      name: scope.name,
      guard: scope.guard,
      action: build_action(scope.action)
    }

    Module.put_attribute(module, :cf_transitions, transition)

    case scope.action do
      %{body: body, cpn_vars: cpn_vars} ->
        Module.put_attribute(
          module,
          :cf_transition_actions,
          {scope.name, body, cpn_vars}
        )

      _other ->
        :ok
    end

    Enum.each(arcs, fn arc ->
      Module.put_attribute(module, :cf_arcs, arc)
    end)

    Module.delete_attribute(module, @scope_attr)
    :ok
  end

  @doc false
  @spec __push_arc__(module(), Arc.t(), String.t(), non_neg_integer()) :: :ok
  def __push_arc__(module, %Arc{} = arc, file, line) do
    case Module.get_attribute(module, @scope_attr) do
      nil ->
        raise CompileError,
          description: "input/output may only be used inside a `transition do ... end` block",
          file: file,
          line: line

      scope ->
        Module.put_attribute(module, @scope_attr, %{scope | arcs: [arc | scope.arcs]})
    end

    :ok
  end

  @doc false
  @spec __set_guard__!(module(), Expression.t(), String.t(), non_neg_integer()) :: :ok
  def __set_guard__!(module, guard, file, line) do
    case Module.get_attribute(module, @scope_attr) do
      nil ->
        raise CompileError,
          description: "guard may only be used inside a `transition do ... end` block",
          file: file,
          line: line

      %{guard: nil} = scope ->
        Module.put_attribute(module, @scope_attr, %{scope | guard: guard})

      %{guard: _existing} ->
        raise CompileError,
          description: "guard already declared in this transition",
          file: file,
          line: line
    end

    :ok
  end

  @doc false
  @spec __set_action__!(module(), map(), String.t(), non_neg_integer()) :: :ok
  def __set_action__!(module, %{} = action, file, line) do
    case Module.get_attribute(module, @scope_attr) do
      nil ->
        raise CompileError,
          description: "action may only be used inside a `transition do ... end` block",
          file: file,
          line: line

      %{action: nil} = scope ->
        Module.put_attribute(module, @scope_attr, %{scope | action: action})

      %{action: _existing} ->
        raise CompileError,
          description: "action already declared in this transition",
          file: file,
          line: line
    end

    :ok
  end

  defp build_action(nil), do: %Action{payload: nil, outputs: []}

  defp build_action(%{code: code}) when is_binary(code) do
    %Action{payload: code, outputs: []}
  end

  @spec unquote_atom!(Macro.t(), String.t(), Macro.Env.t()) :: atom()
  defp unquote_atom!(value, _label, _caller) when is_atom(value), do: value

  defp unquote_atom!(value, label, caller) do
    raise CompileError,
      description: "Expected #{label} to be an atom, got: #{Macro.to_string(value)}",
      file: caller.file,
      line: caller.line
  end

  defp source_file(module) do
    case Module.get_attribute(module, :file) do
      nil -> "nofile"
      src -> to_string(src)
    end
  rescue
    _error -> "nofile"
  end
end
