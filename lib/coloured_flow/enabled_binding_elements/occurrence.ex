defmodule ColouredFlow.EnabledBindingElements.Occurrence do
  @moduledoc """
  When a enabled binding element occurs,
  it consumes a set of markings from input places,
  and produces a set of markings to output places.
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.MultiSet

  import ColouredFlow.EnabledBindingElements.Utils

  @spec occur(
          binding_element :: BindingElement.t(),
          action_outputs :: [ColourSet.value()],
          cpnet :: ColouredPetriNet.t()
        ) :: Occurrence.t()
  def occur(binding_element, action_outputs, cpnet) do
    transition = fetch_transition!(binding_element.transition, cpnet)

    output_vars = if transition.action, do: transition.action.outputs, else: []
    # TODO: return errors
    free_assignments = zip_free_assignments(output_vars, action_outputs)

    binding = Enum.concat(binding_element.binding, free_assignments)

    outputs = get_arcs_with_place(transition, :t_to_p, cpnet)

    to_produce =
      Enum.map(outputs, fn {arc, place} ->
        # TODO: return errors
        {:ok, returning} = ColouredFlow.Expression.eval(arc.expression.expr, binding)

        # TODO: return errors
        {:ok, tokens} = build_tokens(returning, place.colour_set, cpnet)

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

  defp zip_free_assignments(vars, values, acc \\ [])
  defp zip_free_assignments([], [], acc), do: acc

  defp zip_free_assignments([var | vars], [value | values], acc) do
    zip_free_assignments(vars, values, [{var, value} | acc])
  end

  @spec build_tokens(
          # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
          returning :: term(),
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
