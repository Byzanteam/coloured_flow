defmodule ColouredFlow.Runner.Enactment.Catchuping do
  @moduledoc """
  Catchuping is used to update the marking of an enactment to the latest marking.
  """

  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.MultiSet

  @typep tokens() :: Marking.tokens()
  @typep place_tokens() :: {:consume | :produce, Place.name(), tokens()}
  @typep markings_map() :: %{Place.name() => tokens()}

  @doc """
  Apply the occurrences to the marking of the CPNet enactment.
  """
  @spec apply(
          current_markings :: [Marking.t()],
          occurrences :: Enumerable.t(Occurrence.t())
        ) :: {steps :: pos_integer(), [Marking.t()]}
  def apply(current_markings, occurrences) do
    current_markings = to_map(current_markings)

    occurrences
    |> Enum.reduce(
      {0, current_markings},
      fn %Occurrence{} = occurrence, {steps, markings} ->
        new_markings =
          occurrence
          |> to_tokens()
          |> Enum.reduce(markings, &apply_occurrence(&1, &2))

        {steps + 1, new_markings}
      end
    )
    |> then(fn {steps, new_markings} ->
      {steps, to_list(new_markings)}
    end)
  end

  @spec to_map([Marking.t()]) :: markings_map()
  defp to_map(markings) do
    Map.new(markings, fn %Marking{place: place, tokens: tokens} ->
      {place, tokens}
    end)
  end

  @spec to_list(markings_map()) :: [Marking.t()]
  defp to_list(markings) do
    Enum.flat_map(markings, fn {place, tokens} ->
      if MultiSet.size(tokens) > 0 do
        [%Marking{place: place, tokens: tokens}]
      else
        []
      end
    end)
  end

  @spec to_tokens(Occurrence.t()) :: Enumerable.t(place_tokens())
  defp to_tokens(%Occurrence{} = occurrence) do
    Stream.concat(
      Stream.map(occurrence.binding_element.to_consume, fn %Marking{} = marking ->
        {:consume, marking.place, marking.tokens}
      end),
      Stream.map(occurrence.to_produce, fn %Marking{} = marking ->
        {:produce, marking.place, marking.tokens}
      end)
    )
  end

  @spec apply_occurrence(place_tokens(), markings_map()) :: markings_map()
  defp apply_occurrence({:consume, place, tokens}, markings) do
    Map.update!(markings, place, &MultiSet.difference(&1, tokens))
  end

  defp apply_occurrence({:produce, place, tokens}, markings) do
    Map.update(markings, place, tokens, &MultiSet.union(&1, tokens))
  end
end
