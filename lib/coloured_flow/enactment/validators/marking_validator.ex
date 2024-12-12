defmodule ColouredFlow.Enactment.Validators.MarkingValidator do
  @moduledoc """
  The marking validator ensures the place of the marking is valid,
  and the tokens for this place are valid.
  """

  import ColouredFlow.MultiSet, only: [is_empty: 1]

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColourSet.ColourSetMismatch
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Validators.Exceptions.MissingPlaceError
  alias ColouredFlow.MultiSet

  @spec validate(marking, ColouredPetriNet.t()) ::
          {:ok, marking} | {:error, MissingPlaceError.t() | ColourSetMismatch.t()}
        when marking: Marking.t()
  def validate(%Marking{} = marking, %ColouredPetriNet{} = cpnet) do
    with {:ok, place} <- fetch_place(marking.place, cpnet),
         {:ok, _tokens} <- check_tokens(place, marking.tokens, cpnet) do
      {:ok, marking}
    end
  end

  defp fetch_place(place_name, %ColouredPetriNet{} = cpnet) do
    case Enum.find(cpnet.places, &(&1.name == place_name)) do
      nil -> {:error, MissingPlaceError.exception(place: place_name)}
      place -> {:ok, place}
    end
  end

  defp check_tokens(%Place{}, %MultiSet{} = tokens, %ColouredPetriNet{}) when is_empty(tokens) do
    {:ok, tokens}
  end

  defp check_tokens(%Place{} = place, %MultiSet{} = tokens, %ColouredPetriNet{} = cpnet) do
    context = build_of_type_context(cpnet)

    tokens
    |> MultiSet.to_pairs()
    |> Enum.find(fn {_coefficient, value} ->
      match?(:error, ColourSet.Of.of_type(value, ColourSet.Descr.type(place.colour_set), context))
    end)
    |> case do
      nil ->
        {:ok, tokens}

      {_coefficient, value} ->
        {:error, ColourSetMismatch.exception(colour_set: place.colour_set, value: value)}
    end
  end

  defp build_of_type_context(%ColouredPetriNet{} = cpnet) do
    types =
      Map.new(cpnet.colour_sets, fn %ColourSet{name: name, type: type} ->
        {name, type}
      end)

    %{fetch_type: &Map.fetch(types, &1)}
  end
end
