defmodule ColouredFlow.Runner.Enactment.WorkitemConsumption do
  @moduledoc """
  Workitem consumption functions.
  """

  require ColouredFlow.MultiSet

  alias ColouredFlow.MultiSet

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking

  alias ColouredFlow.Runner.Enactment.Workitem

  @doc """
  Pop the workitems from the given list of workitems by the given list of workitem_ids and the expected state.
  """
  @spec pop_workitems([Workitem.t()], [Workitem.id()], expected_state :: state) ::
          {:ok, [Workitem.t(state)], [Workitem.t()]}
          | {
              :error,
              {:workitem_not_found, Workitem.id()}
              | {:workitem_unexpected_state, Workitem.t()}
            }
        when state: Workitem.state()
  def pop_workitems(workitems, workitem_ids, expected_state) do
    {found, remaining} = Enum.split_with(workitems, &(&1.id in workitem_ids))

    workitem_ids
    |> Enum.reduce_while([], fn id, acc ->
      case Enum.find(found, &(&1.id == id)) do
        nil ->
          {:halt, {:error, {:workitem_not_found, id}}}

        %Workitem{state: ^expected_state} = workitem ->
          {:cont, [workitem | acc]}

        %Workitem{} = workitem ->
          {:halt, {:error, {:workitem_unexpected_state, workitem}}}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      workitems -> {:ok, workitems, remaining}
    end
  end

  @spec consume_tokens([Marking.t()], [BindingElement.t()]) ::
          {:ok, [Marking.t()]}
          | {:error, {:unsufficient_tokens, Marking.t()}}
  def consume_tokens(place_markings, binding_elements)

  def consume_tokens(place_markings, []) when is_list(place_markings), do: {:ok, place_markings}

  def consume_tokens([], [%BindingElement{} = binding_element | _rest]) do
    {:error, {:unsufficient_tokens, binding_element.to_consume}}
  end

  def consume_tokens(place_markings, binding_elements)
      when is_list(place_markings) and is_list(binding_elements) do
    to_consume_tokens =
      binding_elements
      |> Stream.flat_map(& &1.to_consume)
      |> Enum.reduce(%{}, fn %Marking{} = marking, acc ->
        Map.update(acc, marking.place, marking.tokens, &MultiSet.union(&1, marking.tokens))
      end)

    place_markings
    |> Enum.reduce_while(
      {[], to_consume_tokens},
      fn %Marking{} = place_marking, {markings, to_consume} ->
        {tokens, to_consume_remaining} = Map.pop(to_consume, place_marking.place, MultiSet.new())

        case MultiSet.safe_difference(place_marking.tokens, tokens) do
          {:ok, remaining_tokens} when MultiSet.is_empty(remaining_tokens) ->
            {:cont, {markings, to_consume_remaining}}

          {:ok, remaining_tokens} ->
            {
              :cont,
              {
                [%Marking{place_marking | tokens: remaining_tokens} | markings],
                to_consume_remaining
              }
            }

          :error ->
            {:halt, {:error, {:unsufficient_tokens, place_marking}}}
        end
      end
    )
    |> case do
      {:error, _reason} = error ->
        error

      {markings, to_consume_remaining} ->
        # Ensure that all tokens are consumed.
        # If not, it indicates an issue, and we should let it crash
        # and restart the process to resolve it.
        unless 0 === map_size(to_consume_remaining) do
          raise """
          The tokens from the place (#{inspect(Map.keys(to_consume_remaining))}) are not consumed.
          There may be an issue on markings and workitems in the corresponding enactment state,
          we should let it crash and restart the process to resolve it.
          """
        end

        {:ok, Enum.reverse(markings)}
    end
  end
end
