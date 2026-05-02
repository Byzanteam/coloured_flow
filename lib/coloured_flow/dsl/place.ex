defmodule ColouredFlow.DSL.Place do
  @moduledoc """
  `place/2` and `initial_marking/2` macros. See `ColouredFlow.DSL` for context.
  """

  alias ColouredFlow.Definition.Place

  @doc """
  Declare a place. The first argument is the place name (atom; converted to a
  string for the underlying `%Place{}`); the second is the colour set name (atom).

  ## Examples

      place :input, :int
      place :output, :int
  """
  defmacro place(name, colour_set) do
    name_value = unquote_atom!(name, "place name")
    colour_set_value = unquote_atom!(colour_set, "place colour set")

    quote do
      @cf_places %Place{
        name: unquote(Atom.to_string(name_value)),
        colour_set: unquote(colour_set_value)
      }
    end
  end

  @doc """
  Declare the initial marking for a place. Multiple `initial_marking/2` calls may
  target different places; they are scattered freely between other declarations.

  ## Examples

      initial_marking :input, ~MS[1, 2, 3]
  """
  defmacro initial_marking(name, marking) do
    name_value = unquote_atom!(name, "initial_marking place name")

    quote do
      @cf_initial_markings {unquote(Atom.to_string(name_value)), unquote(marking)}
    end
  end

  @spec unquote_atom!(Macro.t(), String.t()) :: atom()
  defp unquote_atom!(value, _label) when is_atom(value), do: value

  defp unquote_atom!(value, label) do
    raise ArgumentError, "Expected #{label} to be an atom, got: #{Macro.to_string(value)}"
  end
end
