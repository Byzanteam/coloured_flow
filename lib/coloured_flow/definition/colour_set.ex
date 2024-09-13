defmodule ColouredFlow.Definition.ColourSet do
  @external_resource Path.join(__DIR__, "./colour_set.md")
  @moduledoc File.read!(@external_resource)

  use TypedStructor

  @type name() :: atom()

  @typep primitive_value() ::
           integer()
           | boolean()
           | float()
           | binary()
  @typedoc """
  The value should be a literal quoted expression.

  `Macro.quoted_literal?/1` can be used to check if a quoted expression is a literal.

  ## Valid examples:

      iex> %{name: "Alice", age: 20}
      iex> [1, 2, 3]
      iex> 42

  ## Invalid examples:

      iex> %{name: "Alice", age: age}
      iex> [1, 2, number]
  """

  @type value() ::
          primitive_value()
          # unit
          | {}
          # tuple
          | tuple()
          # map
          | map()
          # enum
          | atom()
          # union
          | {tag :: atom(), value()}
          # list
          | [value()]

  @typep primitive_descr() ::
           {:unit, []}
           | {:integer, []}
           | {:float, []}
           | {:boolean, []}
           | {:binary, []}
  @typep tuple_descr() :: {:tuple, [descr()]}
  @typep map_descr() :: {:map, %{atom() => descr()}}
  @typep enum_descr() :: {:enum, [atom()]}
  @typep union_descr() :: {:union, %{(tag :: atom()) => descr()}}
  @typep list_descr() :: {:list, descr()}

  @type descr() ::
          primitive_descr()
          | tuple_descr()
          | map_descr()
          | enum_descr()
          | union_descr()
          | list_descr()

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :name, name()

    field :type, descr(),
      doc: "The type of the colour set, see module documentation for more information."
  end
end
