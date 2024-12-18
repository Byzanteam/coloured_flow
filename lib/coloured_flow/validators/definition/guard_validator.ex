defmodule ColouredFlow.Validators.Definition.GuardValidator do
  @moduledoc """
  This validator is used to validate guards of the transition.

  A valid guard must satisfy the following properties:
  1. vars must from variables bound to incoming-arcs, or constants
  """

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Validators.Exceptions.InvalidGuardError

  @spec validate(ColouredPetriNet.t()) ::
          {:ok, ColouredPetriNet.t()} | {:error, InvalidGuardError.t()}
  def validate(%ColouredPetriNet{} = cpnet) do
    cpnet.transitions
    |> Enum.find_value(fn %Transition{} = transition ->
      case validate_guard(transition, cpnet) do
        :ok -> nil
        {:error, excetpion} -> excetpion
      end
    end)
    |> case do
      nil -> {:ok, cpnet}
      exception -> {:error, exception}
    end
  end

  defp validate_guard(%Transition{guard: nil}, %ColouredPetriNet{}) do
    :ok
  end

  defp validate_guard(%Transition{guard: %Expression{} = guard}, %ColouredPetriNet{} = cpnet) do
    bound_vars =
      cpnet.arcs
      |> Enum.flat_map(fn
        %Arc{orientation: :p_to_t} = arc -> arc.expression.vars
        %Arc{} -> []
      end)
      |> MapSet.new()

    constants = MapSet.new(cpnet.constants, & &1.name)

    vars_and_consts = MapSet.union(bound_vars, constants)

    diff = MapSet.difference(MapSet.new(guard.vars), vars_and_consts)

    if diff === MapSet.new() do
      :ok
    else
      {
        :error,
        InvalidGuardError.exception(
          reason: :unbound_vars,
          message: """
          Found unbound variables: #{inspect(MapSet.to_list(diff))},
          variables from incoming-arcs are #{inspect(MapSet.to_list(bound_vars))},
          constants are #{inspect(MapSet.to_list(constants))}.
          """
        )
      }
    end
  end
end
