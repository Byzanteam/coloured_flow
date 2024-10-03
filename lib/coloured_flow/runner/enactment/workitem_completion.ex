defmodule ColouredFlow.Runner.Enactment.WorkitemCompletion do
  @moduledoc """
  Workitem completion functions.
  """

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Enactment.Occurrence

  alias ColouredFlow.Runner.Enactment.Workitem

  @doc """
  Complete the workitems with the given free bindings, and return the occurrences.

  ## Parameters
    * `workitem_and_free_bindings` - The workitems and their free binding map
    * `cpnet` - The coloured petri net
  """
  @spec complete(
          workitem_and_free_bindings :: Enumerable.t({Workitem.t(), Occurrence.free_binding()}),
          ColouredPetriNet.t()
        ) :: {:ok, [Occurrence.t()]} | {:error, Exception.t()}
  def complete(workitem_and_free_bindings, cpnet) do
    workitem_and_free_bindings
    |> Enum.reduce_while(
      [],
      fn {%Workitem{} = workitem, free_binding}, acc ->
        case ColouredFlow.EnabledBindingElements.Occurrence.occur(
               workitem.binding_element,
               free_binding,
               cpnet
             ) do
          {:ok, occurrence} -> {:cont, [occurrence | acc]}
          {:error, [exception | _rest]} -> {:halt, {:error, exception}}
        end
      end
    )
    |> case do
      {:error, _exception} = error -> error
      occurrences -> {:ok, occurrences}
    end
  end
end
