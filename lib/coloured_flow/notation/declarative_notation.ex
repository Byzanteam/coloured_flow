defmodule ColouredFlow.Notation.DeclarativeNotation do
  @moduledoc false

  # We bind the declaration to the environment in the specified context,
  # so that we can access them using `binding(context)`.
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Variable

  defmacro colset(declaration) do
    {name, type} = ColouredFlow.Notation.Colset.__colset__(declaration)

    var = Macro.var(name, :colset)

    quote do
      unquote(var) = %ColourSet{
        name: unquote(name),
        type: unquote(type)
      }
    end
  end

  defmacro val(declaration) do
    {name, colour_set, value} = ColouredFlow.Notation.Val.__val__(declaration)

    var = Macro.var(name, :val)

    quote do
      unquote(var) = %Constant{
        name: unquote(name),
        colour_set: unquote(colour_set),
        value: unquote(value)
      }
    end
  end

  defmacro var(declaration) do
    {name, colour_set} = ColouredFlow.Notation.Var.__var__(declaration)

    var = Macro.var(name, :var)

    quote do
      unquote(var) = %Variable{
        name: unquote(name),
        colour_set: unquote(colour_set)
      }
    end
  end
end
