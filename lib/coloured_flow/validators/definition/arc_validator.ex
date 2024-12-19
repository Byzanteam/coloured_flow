defmodule ColouredFlow.Validators.Definition.ArcValidator do
  @moduledoc """
  This validator is used to validate arcs of the transition.

  A valid arc must satisfy the following properties:
  1. vars at incoming arcs must be either variables or constants.
  2. vars at outgoing arcs must be either variables or constants.
  If they are variables, they must be among those bound at the
  incoming arcs or be the outputs of the transition action.
  """

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Validators.Exceptions.InvalidArcError

  @spec validate(ColouredPetriNet.t()) ::
          {:ok, ColouredPetriNet.t()} | {:error, InvalidArcError.t()}
  def validate(%ColouredPetriNet{} = cpnet) do
    vars_and_consts = build_vars_and_consts(cpnet)
    outputs = build_outputs(cpnet)

    cpnet.arcs
    |> Enum.find_value(fn %Arc{} = arc ->
      case validate_arc(arc, vars_and_consts, outputs, cpnet) do
        :ok -> nil
        {:error, reason} -> reason
      end
    end)
    |> case do
      nil -> {:ok, cpnet}
      exception -> {:error, exception}
    end
  end

  defp validate_arc(
         %Arc{orientation: :p_to_t} = arc,
         {vars, consts},
         _outputs,
         %ColouredPetriNet{}
       ) do
    arc.expression.vars
    |> MapSet.new()
    |> MapSet.difference(vars)
    |> MapSet.difference(consts)
    |> MapSet.to_list()
    |> case do
      [] ->
        :ok

      diff ->
        label = if arc.label, do: "(#{arc.label})"

        {
          :error,
          InvalidArcError.exception(
            reason: :incoming_unbound_vars,
            message: """
            Found unbound variables at the incoming arc #{label}: #{inspect(diff)}.
            variables: #{inspect(MapSet.to_list(vars))}
            constants: #{inspect(MapSet.to_list(consts))}
            arc: #{inspect(arc)}
            """
          )
        }
    end
  end

  defp validate_arc(
         %Arc{orientation: :t_to_p} = arc,
         {_vars, consts},
         outputs,
         %ColouredPetriNet{} = cpnet
       ) do
    bound_vars =
      cpnet.arcs
      |> Enum.flat_map(fn
        %Arc{orientation: :p_to_t} = arc -> arc.expression.vars
        %Arc{} -> []
      end)
      |> MapSet.new()

    vars_and_consts =
      bound_vars
      |> MapSet.union(consts)
      |> MapSet.union(Map.get(outputs, arc.transition, []))

    arc.expression.vars
    |> MapSet.new()
    |> MapSet.difference(vars_and_consts)
    |> MapSet.to_list()
    |> case do
      [] ->
        :ok

      diff ->
        label = if arc.label, do: "(#{arc.label})"

        {
          :error,
          InvalidArcError.exception(
            reason: :outgoing_unbound_vars,
            message: """
            Found unbound variables at the outgoing arc #{label}: #{inspect(diff)}.
            variables from incoming-arcs : #{inspect(MapSet.to_list(bound_vars))}
            constants: #{inspect(MapSet.to_list(consts))}
            arc: #{inspect(arc)}
            """
          )
        }
    end
  end

  defp build_vars_and_consts(%ColouredPetriNet{} = cpnet) do
    {
      MapSet.new(cpnet.variables, & &1.name),
      MapSet.new(cpnet.constants, & &1.name)
    }
  end

  defp build_outputs(%ColouredPetriNet{} = cpnet) do
    Map.new(cpnet.transitions, fn %Transition{} = transition ->
      {transition.name, MapSet.new(transition.action.outputs)}
    end)
  end
end
