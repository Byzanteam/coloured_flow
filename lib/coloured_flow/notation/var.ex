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
  defmacro var(declaration) do
    {name, colour_set} = __var__(declaration)

    quote do
      %Variable{
        name: unquote(name),
        colour_set: unquote(colour_set)
      }
    end
  end

  @spec __var__(Macro.t()) :: {name :: Macro.t(), colour_set :: Macro.t()}
  def __var__({:"::", _meta, [name, colour_set]}) do
    name = name |> decompose(:name) |> Macro.escape()
    colour_set = colour_set |> decompose(:colour_set) |> Macro.escape()

    {name, colour_set}
  end

  def __var__(declaration) do
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
