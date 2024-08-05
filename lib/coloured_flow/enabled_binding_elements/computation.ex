defmodule ColouredFlow.EnabledBindingElements.Computation do
  @moduledoc """
  The Computation of Enabled Binding Elements (EBEs).
  """

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.EnabledBindingElements.Binding
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.MultiSet

  import ColouredFlow.EnabledBindingElements.Utils

  @doc """
  Compute the list of enabled binding elements for a given transition and CPNet markings.
  """
  @spec list(
          transition :: Transition.t(),
          cpnet :: ColouredPetriNet.t(),
          markings :: [Marking.t()]
        ) :: [BindingElement.t()]
  def list(transition, cpnet, markings) do
    inputs = get_arcs_with_place(transition, :p_to_t, cpnet)

    arc_bindings =
      Enum.map(inputs, fn {arc, place} ->
        marking = get_marking(place, markings)

        Enum.flat_map(arc.bindings, fn pattern ->
          get_bindings(pattern, MultiSet.to_pairs(marking.tokens))
        end)
      end)

    binding_combinations = Binding.combine(arc_bindings)

    Enum.flat_map(binding_combinations, fn binding ->
      inputs
      |> Enum.reduce_while([], fn {arc, place}, acc ->
        with(
          {:ok, {coefficient, value}} <- eval_arc(arc, binding),
          colour_set = fetch_colour_set!(place.colour_set, cpnet),
          {:ok, ^value} <- ColourSet.Of.of_type(value, colour_set.type),
          {:ok, true} <- eval_transition_guard(transition, binding),
          marking = get_marking(place, markings),
          tokens = MultiSet.duplicate(value, coefficient),
          true <- MultiSet.include?(marking.tokens, tokens)
        ) do
          {:cont, [%Marking{place: place.name, tokens: tokens} | acc]}
        else
          _other -> {:halt, :error}
        end
      end)
      |> case do
        :error ->
          []

        to_consume ->
          [
            %BindingElement{
              transition: transition.name,
              binding: binding,
              to_consume: to_consume
            }
          ]
      end
    end)
  end

  defp get_bindings(pattern, marking, acc \\ [])

  defp get_bindings(_pattern, [], acc) do
    acc
  end

  defp get_bindings(
         {0, {:cpn_bind_variable, value_var}} = pattern,
         [{_coefficient, value} | rest],
         acc
       ) do
    get_bindings(
      pattern,
      rest,
      [[{value_var, value}] | acc]
    )
  end

  defp get_bindings(
         {expected_coefficient, {:cpn_bind_variable, value_var}} = pattern,
         [{coefficient, value} | rest],
         acc
       )
       when is_integer(expected_coefficient) and expected_coefficient > 0 do
    case coefficient - expected_coefficient do
      result when result < 0 ->
        get_bindings(pattern, rest, acc)

      0 ->
        get_bindings(pattern, rest, [[{value_var, value}] | acc])

      result when result > 0 ->
        get_bindings(
          pattern,
          [{result, value} | rest],
          [[{value_var, value}] | acc]
        )
    end
  end

  defp get_bindings(
         {{:cpn_bind_variable, coefficient_name}, {:cpn_bind_variable, value_var}} =
           pattern,
         [{coefficient, value} | rest],
         acc
       ) do
    bindings =
      for coeff <- 0..coefficient do
        [{coefficient_name, coeff}, {value_var, value}]
      end

    get_bindings(pattern, rest, bindings ++ acc)
  end

  defp get_bindings(
         {{:cpn_bind_variable, coefficient_name}, value} = pattern,
         [{coefficient, value} | rest],
         acc
       ) do
    bindings =
      for coeff <- 0..coefficient do
        [{coefficient_name, coeff}]
      end

    get_bindings(pattern, rest, bindings ++ acc)
  end

  defp get_bindings(_pattern, _marking, acc) do
    [[] | acc]
  end

  defp eval_arc(%Arc{} = arc, binding) do
    with({:ok, binding} <- build_binding(arc.expression.vars, binding)) do
      case ColouredFlow.Expression.eval(arc.expression.expr, binding) do
        {:ok, {coefficient, value}} when is_integer(coefficient) and coefficient >= 0 ->
          {:ok, {coefficient, value}}

        {:ok, {coefficient, _value}} ->
          {:error, "The coefficient must be a non-negative integer, got: #{coefficient}"}

        {:ok, result} ->
          {:error, "The result must be a MultiSet pair, got: #{result}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp eval_transition_guard(%Transition{guard: nil}, _binding), do: {:ok, true}

  defp eval_transition_guard(%Transition{} = transition, binding) do
    with({:ok, binding} <- build_binding(transition.guard.vars, binding)) do
      case ColouredFlow.Expression.eval(transition.guard.expr, binding) do
        {:ok, bool} when is_boolean(bool) -> {:ok, bool}
        {:ok, result} -> {:error, "The guard expression must return a boolean, got: #{result}"}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp build_binding(vars, binding) do
    vars
    |> Enum.map_reduce([], fn var, acc ->
      case List.keyfind(binding, var, 0) do
        nil -> {nil, [var]}
        {^var, value} -> {{var, value}, acc}
      end
    end)
    |> case do
      {_binding, []} -> {:ok, binding}
      {_binding, vars} -> {:error, "Unbound variables in the expression: #{inspect(vars)}"}
    end
  end
end