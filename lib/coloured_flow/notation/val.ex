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
  defmacro val({:"::", _meta1, [name, {:=, _meta2, [colour_set, value]}]}) do
    name = decompose(name, :name)
    colour_set = decompose(colour_set, :colour_set)

    quote do
      %Constant{name: unquote(name), colour_set: unquote(colour_set), value: unquote(value)}
    end
  end

  defmacro val(declaration) do
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
