defmodule ColouredFlow.Notation.Val do
  @moduledoc """
  Declare a constant value(`ColouredFlow.Definition.Constant`).
  """

  alias ColouredFlow.Definition.Constant

  @example """
  Examples:

      val all_users   :: user_list() = [
        %{name: "Alice", age: 20},
        %{name: "Bob", age: 30}
      ]
      val all_packets :: list(packet()) = [
        {:data, "Hello"},
        {:ack, 1}
      ]
  """

  @doc """
  Declare a constant value(`ColouredFlow.Definition.Constant`).

  ## Examples

      iex> val name :: string() = "Alice"
      %ColouredFlow.Definition.Constant{name: :name, colour_set: :string, value: "Alice"}
  """
  defmacro val(declaration) do
    {name, colour_set, value} = __val__(declaration)

    quote do
      %Constant{
        name: unquote(name),
        colour_set: unquote(colour_set),
        value: unquote(value)
      }
    end
  end

  @spec __val__(Macro.t()) :: {name :: Macro.t(), colour_set :: Macro.t(), value :: Macro.t()}
  def __val__({:"::", _meta1, [name, {:=, _meta2, [colour_set, value]}]}) do
    name = name |> decompose(:name) |> Macro.escape()
    colour_set = colour_set |> decompose(:colour_set) |> Macro.escape()

    {name, colour_set, value}
  end

  def __val__(declaration) do
    raise """
    Invalid Constant declaration: #{type_to_string(declaration)}
    """
  end

  defp decompose(quoted, identifier) do
    case Macro.decompose_call(quoted) do
      {:__aliases__, _args} ->
        raise """
        Invalid #{identifier} for the constant: `#{type_to_string(quoted)}`

        #{@example}
        """

      {name, []} ->
        name

      _other ->
        raise """
        Invalid #{identifier} for the constant: `#{type_to_string(quoted)}`

        #{@example}
        """
    end
  end

  defp type_to_string(quoted), do: Macro.to_string(quoted)
end
