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

  @doc """
  Declare a variable(`ColouredFlow.Definition.Variable`).

  The colour_set must be a valid colour set name, such as `string()`,
  but the literal colour_set declaration is not allowed.

  ## Examples

      iex> colset string :: binary()
      %ColouredFlow.Definition.ColourSet{name: :string, type: {:binary, []}}
      iex> var name :: string()
      %ColouredFlow.Definition.Variable{name: :name, colour_set: :string}
  """
  defmacro var(declaration) do
    quote do
      require ColouredFlow.Notation.Var
      ColouredFlow.Notation.Var.var(unquote(declaration))
    end
  end

  @doc """
  Declare a constant value(`ColouredFlow.Definition.Constant`).

  ## Examples

      iex> val name :: string() = "Alice"
      %ColouredFlow.Definition.Constant{name: :name, colour_set: :string, value: "Alice"}
  """
  defmacro val(declaration) do
    quote do
      require ColouredFlow.Notation.Val
      ColouredFlow.Notation.Val.val(unquote(declaration))
    end
  end
end
