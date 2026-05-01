defmodule ColouredFlow.EnabledBindingElements.Occurrence do
  @moduledoc """
  When a enabled binding element occurs, it consumes a set of markings from input
  places, and produces a set of markings to output places.
  """

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Variable
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.MultiSet
  alias ColouredFlow.Runner.RuntimeCpnet

  import ColouredFlow.EnabledBindingElements.Utils

  @doc """
  Occurs the binding element with the free variables' binding and the CPNet,
  returns the occurrence of the binding element.
  """
  @spec occur(
          binding_element :: BindingElement.t(),
          free_binding :: [{Variable.name(), ColourSet.value()}],
          runtime_cpnet :: RuntimeCpnet.t()
        ) :: {:ok, Occurrence.t()} | {:error, [Exception.t()]}
  def occur(binding_element, free_binding, %RuntimeCpnet{} = runtime_cpnet) do
    transition = fetch_transition!(binding_element.transition, runtime_cpnet)

    constants = runtime_cpnet.constants
    binding = Enum.concat(binding_element.binding, free_binding)

    outputs = get_arcs_with_place(transition, :t_to_p, runtime_cpnet)

    {to_produce, exceptions} =
      Enum.map_reduce(outputs, [], fn {arc, place}, acc ->
        # place constants into binding
        binding = merge_constants(binding, arc, constants)

        with {:ok, result} <- ColouredFlow.Expression.eval(arc.expression.expr, binding),
             {:ok, tokens} <- build_tokens(result, place.colour_set, runtime_cpnet) do
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
          free_binding: free_binding,
          to_produce: to_produce
        }
      }
    else
      {:error, exceptions}
    end
  end

  defp merge_constants(binding, %Arc{} = arc, constants) do
    constants = constants |> Map.take(arc.expression.vars) |> Enum.to_list()
    # the order of keywords does not matter,
    # as we apply constants to bind expressions earlier
    Keyword.merge(constants, binding)
  end

  @spec build_tokens(
          # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
          binding :: term(),
          colour_set :: ColourSet.name(),
          runtime_cpnet :: RuntimeCpnet.t()
        ) :: {:ok, MultiSet.t()} | {:error, [Exception.t()]}
  defp build_tokens({coefficient, value}, colour_set, %RuntimeCpnet{} = runtime_cpnet)
       when is_integer(coefficient) and coefficient >= 0 do
    alias ColouredFlow.Definition.ColourSet.ColourSetMismatch
    alias ColouredFlow.Definition.ColourSet.Of

    colour_set = fetch_colour_set!(colour_set, runtime_cpnet)
    context = runtime_cpnet.of_type_context

    case Of.of_type(value, colour_set.type, context) do
      {:ok, value} ->
        {:ok, MultiSet.from_pairs([{coefficient, value}])}

      :error ->
        {:error, [ColourSetMismatch.exception(colour_set: colour_set, value: value)]}
    end
  end
end
