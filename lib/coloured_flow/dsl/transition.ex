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
    name_value = unquote_atom!(name, "transition name")
    name_str = Atom.to_string(name_value)

    block =
      case opts do
        list when is_list(list) -> Keyword.get(list, :do)
        _other -> nil
      end

    if is_nil(block) do
      raise ArgumentError,
            "transition/2 requires a `do ... end` block, got: #{inspect(opts)}"
    end

    quote do
      ColouredFlow.DSL.Transition.__open_transition__!(__MODULE__, unquote(name_str))

      unquote(block)

      ColouredFlow.DSL.Transition.__close_transition__!(__MODULE__)
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
    expr_ast = ExpressionHelper.block_to_ast(expression)
    expr = ExpressionHelper.build_from_ast!(expr_ast)

    quote do
      ColouredFlow.DSL.Transition.__set_guard__!(__MODULE__, unquote(Macro.escape(expr)))
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
    expr_ast = ExpressionHelper.block_to_ast(expression)
    code = ExpressionHelper.ast_to_code(expr_ast)

    quote do
      ColouredFlow.DSL.Transition.__set_action__!(__MODULE__, unquote(code))
    end
  end

  @doc false
  @spec __open_transition__!(module(), String.t()) :: :ok
  def __open_transition__!(module, name) when is_atom(module) and is_binary(name) do
    if Module.get_attribute(module, @scope_attr) do
      raise CompileError,
        description: "transition/2 cannot be nested",
        file: source_file(module),
        line: 0
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

    Enum.each(arcs, fn arc ->
      Module.put_attribute(module, :cf_arcs, arc)
    end)

    Module.delete_attribute(module, @scope_attr)
    :ok
  end

  @doc false
  @spec __push_arc__(module(), Arc.t()) :: :ok
  def __push_arc__(module, %Arc{} = arc) do
    case Module.get_attribute(module, @scope_attr) do
      nil ->
        raise CompileError,
          description: "input/output may only be used inside a `transition do ... end` block",
          file: source_file(module),
          line: 0

      scope ->
        Module.put_attribute(module, @scope_attr, %{scope | arcs: [arc | scope.arcs]})
    end

    :ok
  end

  @doc false
  @spec __set_guard__!(module(), Expression.t()) :: :ok
  def __set_guard__!(module, guard) do
    case Module.get_attribute(module, @scope_attr) do
      nil ->
        raise CompileError,
          description: "guard may only be used inside a `transition do ... end` block",
          file: source_file(module),
          line: 0

      scope ->
        Module.put_attribute(module, @scope_attr, %{scope | guard: guard})
    end

    :ok
  end

  @doc false
  @spec __set_action__!(module(), String.t()) :: :ok
  def __set_action__!(module, code) do
    case Module.get_attribute(module, @scope_attr) do
      nil ->
        raise CompileError,
          description: "action may only be used inside a `transition do ... end` block",
          file: source_file(module),
          line: 0

      scope ->
        Module.put_attribute(module, @scope_attr, %{scope | action: code})
    end

    :ok
  end

  defp build_action(nil), do: %Action{payload: nil, outputs: []}

  defp build_action(code) when is_binary(code) do
    %Action{payload: code, outputs: []}
  end

  @spec unquote_atom!(Macro.t(), String.t()) :: atom()
  defp unquote_atom!(value, _label) when is_atom(value), do: value

  defp unquote_atom!(value, label) do
    raise ArgumentError, "Expected #{label} to be an atom, got: #{Macro.to_string(value)}"
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
