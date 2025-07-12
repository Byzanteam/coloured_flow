defmodule ColouredFlow.Validators.Definition.TerminationCriteriaValidator do
  @moduledoc """
  The validator is used to validate weather the Coloured Petri Net termination
  criteria are correct.

  The valid criteria should follow these rules:

  1. The variables in the markings criteria expression should only contain the
     `:markings` variable and constants.
  """

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.TerminationCriteria
  alias ColouredFlow.Definition.TerminationCriteria.Markings
  alias ColouredFlow.Validators.Exceptions.InvalidTerminationCriteriaError

  @intrinsic_vars MapSet.new(~w[markings]a)

  @spec validate(ColouredPetriNet.t()) ::
          {:ok, ColouredPetriNet.t()} | {:error, InvalidTerminationCriteriaError.t()}
  def validate(%ColouredPetriNet{} = cpnet) do
    validate_markings(cpnet)
  end

  defp validate_markings(
         %ColouredPetriNet{
           termination_criteria: %TerminationCriteria{markings: %Markings{} = markings}
         } = cpnet
       ) do
    constants = MapSet.new(cpnet.constants, & &1.name)
    vars = MapSet.new(markings.expression.vars)

    vars
    |> MapSet.difference(MapSet.union(constants, @intrinsic_vars))
    |> MapSet.to_list()
    |> case do
      [] ->
        {:ok, cpnet}

      unknown_vars ->
        {
          :error,
          InvalidTerminationCriteriaError.exception(
            reason: :unknown_vars,
            message: """
            The following variables are unknown in the markings termination criterion: #{inspect(unknown_vars)}.
            Only `markings` and constants can be variables that are bound to the values passed in.
            Constants are #{inspect(MapSet.to_list(constants))}
            """
          )
        }
    end
  end

  defp validate_markings(%ColouredPetriNet{} = cpnet) do
    {:ok, cpnet}
  end
end
