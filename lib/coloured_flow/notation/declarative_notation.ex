defmodule ColouredFlow.Notation.DeclarativeNotation do
  @moduledoc false

  # We bind the declaration to the environment in the specified context,
  # so that we can access them using `binding(context)`.

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Variable

  alias ColouredFlow.Notation.DuplicateDeclarationError

  defmacro colset(declaration) do
    {name, type} = ColouredFlow.Notation.Colset.__colset__(declaration)

    var = Macro.var(name, :colset)

    quote do
      unquote(__MODULE__).__detect_duplicate__(
        binding(:colset),
        unquote(name),
        :colset,
        unquote(Macro.to_string(declaration))
      )

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
      unquote(__MODULE__).__detect_duplicate__(
        binding(:val),
        unquote(name),
        :val,
        unquote(Macro.to_string(declaration))
      )

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
      unquote(__MODULE__).__detect_duplicate__(
        binding(:var),
        unquote(name),
        :var,
        unquote(Macro.to_string(declaration))
      )

      unquote(var) = %Variable{
        name: unquote(name),
        colour_set: unquote(colour_set)
      }
    end
  end

  @spec __detect_duplicate__(
          binding :: Keyword.t(atom()),
          name :: atom(),
          type :: :colset | :val | :var,
          declaration :: String.t()
        ) :: :ok
  def __detect_duplicate__(binding, name, type, declaration) do
    if Keyword.has_key?(binding, name) do
      raise DuplicateDeclarationError,
        name: name,
        type: type,
        declaration: declaration
    end

    :ok
  end
end
