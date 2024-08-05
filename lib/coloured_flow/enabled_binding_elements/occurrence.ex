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
        ) :: Occurrence.t()
  def occur(binding_element, free_assignments, cpnet) do
    transition = fetch_transition!(binding_element.transition, cpnet)

    binding = Enum.concat(binding_element.binding, free_assignments)

    outputs = get_arcs_with_place(transition, :t_to_p, cpnet)

    to_produce =
      Enum.map(outputs, fn {arc, place} ->
        # TODO: return errors
        {:ok, result} = ColouredFlow.Expression.eval(arc.expression.expr, binding)

        # TODO: return errors
        {:ok, tokens} = build_tokens(result, place.colour_set, cpnet)

        %Marking{place: place.name, tokens: tokens}
      end)

    %Occurrence{
      binding_element: binding_element,
      free_assignments: free_assignments,
      to_produce: to_produce
    }
  end

  defp fetch_transition!(name, cpnet) do
    case Enum.find(cpnet.transitions, &(&1.name == name)) do
      nil -> raise "Transition not found: #{name}"
      transition -> transition
    end
  end

  @spec build_tokens(
          # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
          binding :: term(),
          colour_set :: ColourSet.name(),
          cpnet :: ColouredPetriNet.t()
        ) :: {:ok, MultiSet.t()}
  defp build_tokens({coefficient, value}, colour_set, cpnet)
       when is_integer(coefficient) and coefficient >= 0 do
    alias ColouredFlow.Definition.ColourSet.Of
    colour_set = fetch_colour_set!(colour_set, %ColouredPetriNet{} = cpnet)

    {:ok, value} = Of.of_type(value, colour_set.type)

    {:ok, MultiSet.from_pairs([{coefficient, value}])}
  end
end