defmodule ColouredFlow.Notation.Var do
  @moduledoc """
  Declare a variable(`ColouredFlow.Definition.Variable`).
  """

  alias ColouredFlow.Definition.Variable

  @example """
  Valid examples:

      var name :: string()
      var name :: string

  Invalid examples:

      var name :: {binary(), binary()}
  """

  @doc """
  Declare a variable(`ColouredFlow.Definition.Variable`).

  ## Examples

      iex> var name :: string()
      %ColouredFlow.Definition.Variable{name: :name, colour_set: :string}
  """
  defmacro var({:"::", _meta, [name, colour_set]}) do
    name = decompose(name, :name)
    colour_set = decompose(colour_set, :colour_set)

    Macro.escape(%Variable{name: name, colour_set: colour_set})
  end

  defmacro var(declaration) do
    raise """
    Invalid variable declaration: #{type_to_string(declaration)}
    """
  end

  defp decompose(quoted, identifier) do
    case Macro.decompose_call(quoted) do
      {:__aliases__, _args} ->
        raise """
        Invalid #{identifier} for the variable: `#{type_to_string(quoted)}`

        #{@example}
        """

      {name, []} ->
        name

      _other ->
        raise """
        Invalid #{identifier} for the variable: `#{type_to_string(quoted)}`

        #{@example}
        """
    end
  end

  defp type_to_string(quoted), do: Macro.to_string(quoted)
end
