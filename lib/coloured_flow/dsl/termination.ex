defmodule ColouredFlow.DSL.Termination do
  @moduledoc """
  `termination/1` and `on_markings/1` macros. See `ColouredFlow.DSL` for context.

  Currently only `on_markings/1` is supported. Future criterion kinds plug in here
  without changing call sites.
  """

  alias ColouredFlow.DSL.ExpressionHelper

  alias ColouredFlow.Definition.TerminationCriteria
  alias ColouredFlow.Definition.TerminationCriteria.Markings

  @scope_attr :__cf_termination_scope__

  @doc """
  Declare termination criteria. The block accepts criterion-specific sub-macros.
  Currently only `on_markings/1` is supported.

  ## Examples

      termination do
        on_markings do
          match?(%{"output" => out}, markings) and
            multi_set_coefficient(out, 1) >= 5
        end
      end
  """
  defmacro termination(opts \\ []) do
    block =
      case opts do
        list when is_list(list) -> Keyword.get(list, :do)
        _other -> nil
      end

    if is_nil(block) do
      raise ArgumentError,
            "termination/1 requires a `do ... end` block, got: #{inspect(opts)}"
    end

    quote do
      ColouredFlow.DSL.Termination.__open_termination__!(__MODULE__)

      unquote(block)

      ColouredFlow.DSL.Termination.__close_termination__!(__MODULE__)
    end
  end

  @doc """
  Boolean expression over the special variable `markings` (a map of place name →
  token multiset). Returning a truthy value terminates the enactment with reason
  `:explicit`.

  ## Examples

      on_markings do
        match?(%{"output" => out}, markings) and
          multi_set_coefficient(out, 1) >= 5
      end
  """
  defmacro on_markings(expression) do
    expr_ast = ExpressionHelper.block_to_ast(expression)
    expression = ExpressionHelper.build_from_ast!(expr_ast)
    markings = %Markings{expression: expression}

    quote do
      ColouredFlow.DSL.Termination.__set_markings__!(
        __MODULE__,
        unquote(Macro.escape(markings))
      )
    end
  end

  @doc false
  @spec __open_termination__!(module()) :: :ok
  def __open_termination__!(module) do
    if Module.get_attribute(module, @scope_attr) do
      raise CompileError,
        description: "termination/1 cannot be nested",
        file: source_file(module),
        line: 0
    end

    Module.put_attribute(module, @scope_attr, %{markings: nil})
    :ok
  end

  @doc false
  @spec __close_termination__!(module()) :: :ok
  def __close_termination__!(module) do
    scope = Module.get_attribute(module, @scope_attr)

    if is_nil(scope) do
      raise CompileError,
        description: "internal error: closing termination that wasn't opened",
        file: source_file(module),
        line: 0
    end

    if scope.markings || true do
      criteria = %TerminationCriteria{markings: scope.markings}
      Module.put_attribute(module, :cf_termination_criteria, criteria)
    end

    Module.delete_attribute(module, @scope_attr)
    :ok
  end

  @doc false
  @spec __set_markings__!(module(), Markings.t()) :: :ok
  def __set_markings__!(module, %Markings{} = markings) do
    case Module.get_attribute(module, @scope_attr) do
      nil ->
        raise CompileError,
          description: "on_markings may only be used inside a `termination do ... end` block",
          file: source_file(module),
          line: 0

      scope ->
        Module.put_attribute(module, @scope_attr, %{scope | markings: markings})
    end

    :ok
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
