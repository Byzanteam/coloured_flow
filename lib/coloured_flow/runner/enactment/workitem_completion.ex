defmodule ColouredFlow.Runner.Enactment.WorkitemCompletion do
  @moduledoc """
  Workitem completion functions.
  """

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Enactment.Occurrence

  alias ColouredFlow.EnabledBindingElements.Utils

  alias ColouredFlow.Runner.Enactment.Workitem

  @doc """
  Complete the workitems with the given free bindings, and return the occurrences.

  ## Parameters
    * `workitem_and_outputs` - The workitems and their free binding (outputs)
    * `cpnet` - The coloured petri net
  """
  @spec complete(
          workitem_and_outputs :: Enumerable.t({Workitem.t(:started), Occurrence.free_binding()}),
          ColouredPetriNet.t()
        ) :: {:ok, [{Workitem.t(:completed), Occurrence.t()}]} | {:error, Exception.t()}
  def complete(workitem_and_outputs, cpnet) do
    workitem_and_outputs
    |> Enum.reduce_while(
      [],
      fn {%Workitem{state: :started} = workitem, ouputs}, acc ->
        transition = fetch_transition!(workitem, cpnet)

        with(
          {:ok, ouputs} <- validate_outputs(transition, ouputs, cpnet),
          {:ok, occurrence} <- occur(workitem, ouputs, cpnet)
        ) do
          {:cont, [{%Workitem{workitem | state: :completed}, occurrence} | acc]}
        else
          {:error, {:unbound_action_output, args}} ->
            alias ColouredFlow.Runner.Exceptions.UnboundActionOutput

            exception = UnboundActionOutput.exception([{:transition, transition.name} | args])

            {:halt, {:error, exception}}

          {:error, {:colour_set_mismatch, args}} ->
            exception = ColourSet.ColourSetMismatch.exception(args)

            {:halt, {:error, exception}}

          {:error, exception} when is_exception(exception) ->
            {:halt, {:error, exception}}
        end
      end
    )
    |> case do
      {:error, _exception} = error -> error
      workitem_occurrences -> {:ok, Enum.reverse(workitem_occurrences)}
    end
  end

  defp fetch_transition!(%Workitem{} = workitem, %ColouredPetriNet{} = cpnet) do
    Utils.fetch_transition!(workitem.binding_element.transition, cpnet)
  end

  @spec validate_outputs(Transition.t(), Occurrence.free_binding(), ColouredPetriNet.t()) ::
          {:ok, [Occurrence.free_binding()]}
          | {:error, {:unbound_action_output | :colour_set_mismatch, Keyword.t()}}
  defp validate_outputs(%Transition{action: %Action{outputs: output_vars}}, outputs, cpnet) do
    context = build_of_type_context(cpnet)

    output_vars
    |> Enum.reduce_while([], fn output_var, acc ->
      with(
        {:ok, value} <- fetch_output(outputs, output_var),
        output_var = fetch_variable!(output_var, cpnet),
        colour_set = fetch_colour_set!(output_var.colour_set, cpnet),
        {:ok, value} <- check_output_type(value, colour_set, context)
      ) do
        {:cont, [{output_var.name, value} | acc]}
      else
        {:error, _exception} = error -> {:halt, error}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      outputs -> {:ok, outputs}
    end
  end

  defp fetch_output(outputs, output_var) do
    with :error <- Keyword.fetch(outputs, output_var) do
      {:error, {:unbound_action_output, output: output_var}}
    end
  end

  defp fetch_variable!(colour_set, %ColouredPetriNet{} = cpnet) do
    Utils.fetch_variable!(colour_set, cpnet)
  end

  defp fetch_colour_set!(colour_set, %ColouredPetriNet{} = cpnet) do
    Utils.fetch_colour_set!(colour_set, cpnet)
  end

  defp build_of_type_context(%ColouredPetriNet{} = cpnet) do
    Utils.build_of_type_context(cpnet)
  end

  defp check_output_type(value, %ColourSet{} = colour_set, context) do
    with :error <- ColourSet.Of.of_type(value, colour_set.type, context) do
      {:error, {:colour_set_mismatch, colour_set: colour_set, value: value}}
    end
  end

  defp occur(%Workitem{} = workitem, free_binding, cpnet) do
    alias ColouredFlow.EnabledBindingElements.Occurrence

    with {:error, [exception | _rest]} <-
           Occurrence.occur(workitem.binding_element, free_binding, cpnet) do
      {:error, exception}
    end
  end
end
