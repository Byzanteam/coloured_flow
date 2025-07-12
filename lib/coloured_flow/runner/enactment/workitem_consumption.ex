defmodule ColouredFlow.Runner.Enactment.WorkitemConsumption do
  @moduledoc """
  Workitem consumption functions.
  """

  require ColouredFlow.MultiSet

  alias ColouredFlow.MultiSet

  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking

  alias ColouredFlow.Runner.Enactment.Workitem

  @typep workitems(state) :: %{Workitem.id() => Workitem.t(state)}
  @typep workitems() :: workitems(Workitem.state())

  @doc """
  Pop the workitems from the given list of workitems by the given list of
  workitem_ids and the expected state.
  """
  @spec pop_workitems(workitems(), [Workitem.id()], expected_state :: state) ::
          {:ok, workitems(state), workitems()}
          | {
              :error,
              {:workitem_not_found, Workitem.id()}
              | {:workitem_unexpected_state, Workitem.t()}
            }
        when state: Workitem.state()
  def pop_workitems(workitems, workitem_ids, expected_state) do
    workitem_ids
    |> Enum.reduce_while({%{}, workitems}, fn workitem_id, {popped, remaining} ->
      case Map.pop(remaining, workitem_id) do
        {%Workitem{state: ^expected_state} = workitem, remaining} ->
          {:cont, {Map.put(popped, workitem_id, workitem), remaining}}

        {%Workitem{} = workitem, _remaining} ->
          {:halt, {:error, {:workitem_unexpected_state, workitem}}}

        {nil, _remaining} ->
          {:halt, {:error, {:workitem_not_found, workitem_id}}}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      {popped, remaining} -> {:ok, popped, remaining}
    end
  end

  @typep markings() :: %{Place.name() => Marking.t()}

  @spec consume_tokens(markings(), [BindingElement.t()]) ::
          {:ok, markings()}
          | {:error, {:unsufficient_tokens, Marking.t()}}
  def consume_tokens(place_markings, binding_elements)

  def consume_tokens(place_markings, []) when is_map(place_markings),
    do: {:ok, place_markings}

  def consume_tokens(place_markings, binding_elements)
      when is_map(place_markings) and is_list(binding_elements) do
    binding_elements
    |> Stream.flat_map(& &1.to_consume)
    |> Enum.reduce(%{}, fn %Marking{} = marking, acc ->
      Map.update(acc, marking.place, marking.tokens, &MultiSet.union(&1, marking.tokens))
    end)
    |> Enum.reduce_while(place_markings, fn
      {place, to_consume_tokens}, acc when is_map_key(acc, place) ->
        place_marking = Map.fetch!(acc, place)

        case MultiSet.safe_difference(place_marking.tokens, to_consume_tokens) do
          {:ok, remaining_tokens} when MultiSet.is_empty(remaining_tokens) ->
            {:cont, Map.delete(acc, place)}

          {:ok, remaining_tokens} ->
            {:cont, Map.put(acc, place, %Marking{place_marking | tokens: remaining_tokens})}

          :error ->
            {:halt, {:error, {:unsufficient_tokens, place_marking}}}
        end

      {place, _to_consume_tokens}, _acc ->
        {:halt, {:error, {:unsufficient_tokens, %Marking{place: place, tokens: []}}}}
    end)
    |> case do
      {:error, _reason} = error -> error
      markings -> {:ok, markings}
    end
  end
end
