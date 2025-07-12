defmodule ColouredFlow.Validators.Enactment.MarkingsValidator do
  @moduledoc """
  The markings validator ensures that the place of markings is valid, and that the
  tokens for the corresponding place are valid.
  """

  import ColouredFlow.MultiSet, only: [is_empty: 1]

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.MultiSet
  alias ColouredFlow.Validators.Exceptions.InvalidMarkingError

  @spec validate(markings, ColouredPetriNet.t()) ::
          {:ok, markings} | {:error, InvalidMarkingError.t()}
        when markings: [Marking.t()]
  def validate([], %ColouredPetriNet{}), do: {:ok, []}

  def validate(markings, %ColouredPetriNet{} = cpnet) when is_list(markings) do
    context = build_of_type_context(cpnet)

    markings
    |> Enum.find_value(fn %Marking{} = marking ->
      with {:ok, place} <- fetch_place(marking, cpnet),
           {:ok, _tokens} <- check_tokens(place, marking, context) do
        false
      else
        {:error, _exception} = error -> error
      end
    end)
    |> case do
      nil -> {:ok, markings}
      {:error, _exception} = error -> error
    end
  end

  defp build_of_type_context(%ColouredPetriNet{} = cpnet) do
    types =
      Map.new(cpnet.colour_sets, fn %ColourSet{name: name, type: type} ->
        {name, type}
      end)

    %{fetch_type: &Map.fetch(types, &1)}
  end

  defp fetch_place(%Marking{} = marking, %ColouredPetriNet{} = cpnet) do
    case Enum.find(cpnet.places, &(&1.name == marking.place)) do
      nil ->
        {
          :error,
          InvalidMarkingError.exception(
            reason: :missing_place,
            message: """
            The place of the marking #{marking.place} is not found from the cpnet,
            the marking is #{inspect(marking)}.
            """
          )
        }

      place ->
        {:ok, place}
    end
  end

  defp check_tokens(%Place{}, %Marking{tokens: %MultiSet{} = tokens}, _context)
       when is_empty(tokens) do
    {:ok, tokens}
  end

  defp check_tokens(%Place{} = place, %Marking{} = marking, context) do
    marking.tokens
    |> MultiSet.to_pairs()
    |> Enum.find(fn {_coefficient, value} ->
      match?(:error, ColourSet.Of.of_type(value, ColourSet.Descr.type(place.colour_set), context))
    end)
    |> case do
      nil ->
        {:ok, marking.tokens}

      {_coefficient, value} ->
        {:error,
         InvalidMarkingError.exception(
           reason: :invalid_tokens,
           message: """
           The value of the token #{inspect(value)} does not match the colour set #{inspect(place.colour_set)},
            the marking is #{inspect(marking)}.
           """
         )}
    end
  end
end
