defmodule ColouredFlow.Runner.Storage.Schemas.Types do
  @moduledoc """
  This module defines the types used in the ColouredFlow.Runner.Storage.Schemas module.
  """

  @typedoc """
  The maybe type. Represents a value that can either be of type `t` or `nil`.
  """
  @type maybe(t) :: t | nil

  @typedoc """
  The type for a primary_key or foreign_key, represented as a UUID.
  """
  @type id() :: Ecto.UUID.t()

  @typedoc """
  Represents an optional UUID, which can be `nil`.
  """
  @type maybe_id() :: maybe(id())

  @typedoc """
  Represents an Ecto association, which can either be not loaded or of type `t`.
  """
  @type association(t) :: Ecto.Association.NotLoaded.t() | t

  @typedoc """
  Represents an optional Ecto association, which can either be
  not loaded, of type `t`, or `nil`.
  """
  @type maybe_association(t) :: Ecto.Association.NotLoaded.t() | maybe(t)

  @doc """
  Make [sum type](https://en.wikipedia.org/wiki/Tagged_union).

      iex> ColouredFlow.Runner.Storage.Schemas.Types.make_sum_type([:foo, :bar, :baz])
      quote do :foo | :bar | :baz end
  """
  @spec make_sum_type([atom(), ...]) :: Macro.t()
  def make_sum_type(types) do
    types
    |> Enum.reverse()
    |> Enum.reduce(fn type, acc when is_atom(type) ->
      quote do: unquote(type) | unquote(acc)
    end)
  end
end
