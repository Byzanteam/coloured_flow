defmodule ColouredFlow.Types do
  @moduledoc """
  This module defines the types used in the ColouredFlow module.
  """

  @typedoc """
  The maybe type. Represents a value that can either be of type `t` or `nil`.
  """
  @type maybe(t) :: t | nil

  @doc """
  Make [sum type](https://en.wikipedia.org/wiki/Tagged_union).

      iex> ColouredFlow.Runner.Storage.Schemas.Types.make_sum_type([:foo, :bar, :baz])
      quote do :foo | :bar | :baz end
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec make_sum_type([term(), ...]) :: Macro.t()
  def make_sum_type(types) do
    types
    |> Enum.reverse()
    |> Enum.reduce(fn type, acc ->
      case Macro.validate(type) do
        :ok ->
          quote do: unquote(type) | unquote(acc)

        {:error, _remainder} ->
          raise ArgumentError, """
          Expected a valid quoted type, but got: #{inspect(type)},
          You may use `Macro.escape/1` to escape the type.
          """
      end
    end)
  end
end
