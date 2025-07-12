defmodule ColouredFlow.Notation.Declaration do
  @moduledoc """
  Declare ColouredFlow Colour Sets, Variables, and Constants in a block string.
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Variable

  @doc """
  Compile a block string of ColouredFlow declarations into a list of definitions.

  ## Example:

      iex> ColouredFlow.Notation.Declaration.compile(~S"""
      ...>   colset name :: binary()
      ...>   var name :: name()
      ...>   val name :: name() = "Alice"
      ...> """)
      {:ok, [
        %ColouredFlow.Definition.ColourSet{name: :name, type: {:binary, []}},
        %ColouredFlow.Definition.Variable{name: :name, colour_set: :name},
        %ColouredFlow.Definition.Constant{name: :name, colour_set: :name, value: "Alice"}
      ]}
  """
  @spec compile(inscription :: binary()) ::
          {:ok, [ColourSet.t() | Constant.t() | Variable.t()]}
          | {:error, [Exception.t()]}
  def compile(inscription) when is_binary(inscription) do
    with(
      {:ok, quoted, _unbound_vars} <- compile_inscription(inscription),
      quoted = decorate_inscription(quoted),
      {:ok, result} <- ColouredFlow.Expression.eval(quoted, [], make_env())
    ) do
      {:ok, result}
    else
      {:error, exceptions} when is_list(exceptions) ->
        {:error, exceptions}

      {:error, exception} when is_exception(exception) ->
        {:error, [exception]}
    end
  end

  defp compile_inscription(inscription) do
    with {:error, {_meta, message_info, _token}} <- ColouredFlow.Expression.compile(inscription) do
      {:error, ArgumentError.exception(message_info)}
    end
  end

  defp make_env do
    import ColouredFlow.Notation.DeclarativeNotation, only: :macros, warn: false

    __ENV__
  end

  # We bind every declaration to the environment so that we can access it
  # by `binding(ctx)`.
  defp decorate_inscription(quoted) do
    quote do
      unquote(quoted)
      binding = binding(:colset) ++ binding(:val) ++ binding(:var)
      Keyword.values(binding)
    end
  end
end
