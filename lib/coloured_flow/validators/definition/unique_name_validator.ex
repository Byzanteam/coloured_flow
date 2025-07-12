defmodule ColouredFlow.Validators.Definition.UniqueNameValidator do
  @moduledoc """
  This validator ensures that names within a ColouredFlow definition are unique.
  It validates the uniqueness of:

  - Colour sets
  - Variables and constants
  - Places
  - Transitions

  If a duplicate name is found within any of these categories, an error is
  returned immediately. Otherwise, the validation is passed.
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable

  alias ColouredFlow.Validators.Exceptions.UniqueNameViolationError

  @spec validate(ColouredPetriNet.t()) ::
          {:ok, ColouredPetriNet.t()} | {:error, UniqueNameViolationError.t()}
  def validate(%ColouredPetriNet{} = cpnet) do
    [
      colour_set: & &1.colour_sets,
      variable_and_constant: &(&1.variables ++ &1.constants),
      place: & &1.places,
      transition: & &1.transitions
    ]
    |> Stream.map(fn {scope, get_items_fun} ->
      {scope, get_items_fun.(cpnet)}
    end)
    |> Enum.find_value({:ok, cpnet}, fn {scope, items} ->
      case validate(scope, items) do
        :ok -> nil
        {:error, exception} -> {:error, exception}
      end
    end)
  end

  defp validate(scope, items) do
    items
    |> Enum.reduce_while(MapSet.new(), fn item, acc ->
      name = get_name(item)

      if MapSet.member?(acc, name) do
        {:halt, UniqueNameViolationError.exception(scope: scope, name: name)}
      else
        {:cont, MapSet.put(acc, name)}
      end
    end)
    |> case do
      exception when is_exception(exception) -> {:error, exception}
      _names -> :ok
    end
  end

  defp get_name(%ColourSet{name: name}), do: name
  defp get_name(%Constant{name: name}), do: name
  defp get_name(%Place{name: name}), do: name
  defp get_name(%Transition{name: name}), do: name
  defp get_name(%Variable{name: name}), do: name
end
