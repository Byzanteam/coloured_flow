defmodule ColouredFlow.Builder.SetActionOutputs do
  @moduledoc """
  This phase is responsible for setting the outputs of the actions
  according to the expressions from arcs and the transition guard.
  """

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Transition

  @spec run(ColouredPetriNet.t()) :: ColouredPetriNet.t()
  def run(%ColouredPetriNet{} = cpnet) do
    transitions =
      Enum.map(cpnet.transitions, fn %Transition{} = transition ->
        vars = vars(cpnet)

        {inputs_ms, outputs_ms} =
          Enum.reduce(
            vars,
            {_inputs = MapSet.new(), _outputs = MapSet.new()},
            fn
              {:input_arc, var}, {inputs, outputs} -> {MapSet.put(inputs, var), outputs}
              {:output_arc, var}, {inputs, outputs} -> {inputs, MapSet.put(outputs, var)}
            end
          )

        # We need to sort the outputs to make the list deterministic
        outputs = outputs_ms |> MapSet.difference(inputs_ms) |> Enum.sort()

        Map.update!(transition, :action, fn
          %Action{} = action -> %Action{action | outputs: outputs}
          nil -> %Action{outputs: outputs}
        end)
      end)

    %ColouredPetriNet{cpnet | transitions: transitions}
  end

  defp vars(%ColouredPetriNet{} = cpnet) do
    Stream.flat_map(cpnet.arcs, fn
      %Arc{orientation: :p_to_t} = arc -> get_vars(:input_arc, arc.expression)
      %Arc{orientation: :t_to_p} = arc -> get_vars(:output_arc, arc.expression)
    end)
  end

  defp get_vars(_scope, nil), do: []
  defp get_vars(scope, %Expression{} = expression), do: Stream.map(expression.vars, &{scope, &1})
end
