defmodule ColouredFlow.Validators.Definition.ActionValidator do
  @moduledoc """
  This validator is used to validate the action of the transition.

  A valid action must satisfy the following properties:

  1. output vars must be variables that cannot be constants.
  1. output vars must be variables that are not bound at the incoming arcs.
  """

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Validators.Exceptions.InvalidActionError

  @spec validate(ColouredPetriNet.t()) ::
          {:ok, ColouredPetriNet.t()} | {:error, InvalidActionError.t()}
  def validate(%ColouredPetriNet{} = cpnet) do
    vars = get_vars(cpnet)

    cpnet.transitions
    |> Enum.find_value(fn %Transition{} = transition ->
      case validate_action(transition, vars, cpnet) do
        :ok -> nil
        {:error, excetpion} -> excetpion
      end
    end)
    |> case do
      nil -> {:ok, cpnet}
      exception -> {:error, exception}
    end
  end

  defp get_vars(%ColouredPetriNet{} = cpnet) do
    MapSet.new(cpnet.variables, & &1.name)
  end

  defp validate_action(
         %Transition{action: %Action{} = action} = transition,
         vars,
         %ColouredPetriNet{} = cpnet
       ) do
    output_vars = MapSet.new(action.outputs)

    with :ok <- check_output_not_variable(output_vars, vars) do
      incoming_bound_vars = get_incoming_bound_vars(transition, cpnet)
      check_bound_output(output_vars, incoming_bound_vars)
    end
  end

  defp check_output_not_variable(output_vars, vars) do
    output_vars
    |> MapSet.difference(vars)
    |> MapSet.to_list()
    |> case do
      [] ->
        :ok

      missing_vars ->
        {
          :error,
          InvalidActionError.exception(
            reason: :output_not_variable,
            message: """
            The following output vars are not variables: #{inspect(missing_vars)}
            """
          )
        }
    end
  end

  defp check_bound_output(output_vars, incoming_bound_vars) do
    output_vars
    |> MapSet.intersection(incoming_bound_vars)
    |> MapSet.to_list()
    |> case do
      [] ->
        :ok

      bound_vars ->
        {
          :error,
          InvalidActionError.exception(
            reason: :bound_output,
            message: """
            The following output vars are bound at the incoming arcs: #{inspect(bound_vars)}
            """
          )
        }
    end
  end

  defp get_incoming_bound_vars(%Transition{name: transition_name}, %ColouredPetriNet{} = cpnet) do
    cpnet.arcs
    |> Stream.filter(&match?(%Arc{orientation: :p_to_t, transition: ^transition_name}, &1))
    |> Stream.flat_map(fn %Arc{} = arc -> arc.expression.vars end)
    |> MapSet.new()
  end
end
