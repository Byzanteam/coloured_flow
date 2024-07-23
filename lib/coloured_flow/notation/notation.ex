defmodule ColouredFlow.Notation do
  @moduledoc """
  This module provides a macro for declarations of coloured petri nets.
  """

  @doc """
  Declare a colour set(`ColouredFlow.Definition.ColourSet`).

  ## Examples

      iex> colset name :: binary()
      %ColouredFlow.Definition.ColourSet{name: :name, type: {:binary, []}}

  See more examples at `ColouredFlow.Definition.ColourSet`.
  """
  defmacro colset(declaration) do
    quote do
      require ColouredFlow.Notation.Colset
      ColouredFlow.Notation.Colset.colset(unquote(declaration))
    end
  end
end
