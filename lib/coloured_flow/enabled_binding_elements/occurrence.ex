defmodule ColouredFlow.EnabledBindingElements.Occurrence do
  @moduledoc """
  When a enabled binding element occurs,
  it consumes a set of markings from input places,
  and produces a set of markings to output places.
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Variable
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.MultiSet

  import ColouredFlow.EnabledBindingElements.Utils

  @doc """
  Occurs the binding element with the free assignments and the CPNet,
  returns the occurrence of the binding element.
  """
  @spec occur(
          binding_element :: BindingElement.t(),
          free_assignments :: [{Variable.name(), ColourSet.value()}],
          cpnet :: ColouredPetriNet.t()
        ) :: {:ok, Occurrence.t()} | {:error, [Exception.t()]}
  def occur(binding_element, free_assignments, cpnet) do
    transition = fetch_transition!(binding_element.transition, cpnet)

    binding = Enum.concat(binding_element.binding, free_assignments)

    outputs = get_arcs_with_place(transition, :t_to_p, cpnet)

    {to_produce, exceptions} =
      Enum.map_reduce(outputs, [], fn {arc, place}, acc ->
        with {:ok, result} <- ColouredFlow.Expression.eval(arc.expression.expr, binding),
             {:ok, tokens} <- build_tokens(result, place.colour_set, cpnet) do
          {%Marking{place: place.name, tokens: tokens}, acc}
        else
          {:error, exceptions} -> {:error, acc ++ exceptions}
        end
      end)

    if match?([], exceptions) do
      {
        :ok,
        %Occurrence{
          binding_element: binding_element,
          free_assignments: free_assignments,
          to_produce: to_produce
        }
      }
    else
      {:error, exceptions}
    end
  end

  @spec build_tokens(
          # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
          binding :: term(),
          colour_set :: ColourSet.name(),
          cpnet :: ColouredPetriNet.t()
        ) :: {:ok, MultiSet.t()} | {:error, [Exception.t()]}
  defp build_tokens({coefficient, value}, colour_set, cpnet)
       when is_integer(coefficient) and coefficient >= 0 do
    alias ColouredFlow.Definition.ColourSet.ColourSetMismatch
    alias ColouredFlow.Definition.ColourSet.Of

    colour_set = fetch_colour_set!(colour_set, %ColouredPetriNet{} = cpnet)

    case Of.of_type(value, colour_set.type) do
      {:ok, value} ->
        {:ok, MultiSet.from_pairs([{coefficient, value}])}

      :error ->
        {:error, [ColourSetMismatch.exception(colour_set: colour_set, value: value)]}
    end
  end
end
