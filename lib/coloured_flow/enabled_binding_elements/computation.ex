defmodule ColouredFlow.EnabledBindingElements.Computation do
  @moduledoc """
  The Computation of Enabled Binding Elements (EBEs).
  """

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Place
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
          markings :: %{Place.name() => Marking.t()}
        ) :: [BindingElement.t()]
  def list(transition, cpnet, markings) do
    inputs = get_arcs_with_place(transition, :p_to_t, cpnet)
    constants = build_constants(cpnet)

    arc_bindings =
      inputs
      |> Enum.map(fn {arc, place} ->
        marking = get_marking(place, markings)

        arc.expression.expr
        |> ColouredFlow.Expression.Arc.extract_bind_exprs()
        |> Enum.map(fn arc_bind_expr ->
          # replace variables with constants
          # NOTE (fahchen): only unbound vars can be constants
          constants = Map.take(constants, arc.expression.vars)
          Binding.apply_constants_to_bind_expr(arc_bind_expr, constants)
        end)
        |> Enum.flat_map(fn arc_bind_expr ->
          Binding.match_bag(marking.tokens, arc_bind_expr)
        end)
      end)
      |> reject_invalid_bandings(cpnet)

    binding_combinations = Binding.combine(arc_bindings)

    Enum.flat_map(binding_combinations, fn binding ->
      inputs
      |> Enum.reduce_while([], fn {arc, place}, acc ->
        arc_binding = merge_constants(binding, arc, constants)

        with(
          {:ok, {coefficient, value}} <- eval_arc(arc, arc_binding),
          colour_set = fetch_colour_set!(place.colour_set, cpnet),
          of_type_context = build_of_type_context(cpnet),
          {:ok, ^value} <- ColourSet.Of.of_type(value, colour_set.type, of_type_context),
          guard_binding = merge_constants(binding, transition, constants),
          {:ok, true} <- eval_transition_guard(transition, guard_binding),
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
          # binding here should not contain constants
          [BindingElement.new(transition.name, binding, to_consume)]
      end
    end)
  end

  @spec reject_invalid_bandings([[[BindingElement.binding()]]], ColouredPetriNet.t()) ::
          [[[BindingElement.binding()]]]
  defp reject_invalid_bandings(bindings_list, cpnet) do
    of_type_context = build_of_type_context(cpnet)

    valid_binding? = fn binding ->
      Enum.all?(binding, fn {name, value} ->
        variable = fetch_variable!(name, cpnet)

        match?(
          {:ok, _value},
          ColourSet.Of.of_type(value, {variable.colour_set, []}, of_type_context)
        )
      end)
    end

    Enum.map(bindings_list, fn arc_bindings ->
      Enum.filter(arc_bindings, valid_binding?)
    end)
  end

  defp merge_constants(binding, %Arc{} = arc, constants) do
    constants = constants |> Map.take(arc.expression.vars) |> Enum.to_list()
    # the order of keywords does not matter,
    # as we apply constants to bind expressions earlier
    Keyword.merge(constants, binding)
  end

  defp merge_constants(binding, %Transition{guard: %Expression{vars: vars}}, constants) do
    constants = constants |> Map.take(vars) |> Enum.to_list()

    # constants take priority over binding
    Keyword.merge(binding, constants)
  end

  defp merge_constants(binding, %Transition{}, _constants), do: binding

  defp eval_arc(%Arc{} = arc, binding) do
    with({:ok, binding} <- build_binding(arc.expression.vars, binding)) do
      case ColouredFlow.Expression.eval(arc.expression.expr, binding) do
        {:ok, {:ok, {coefficient, value}}} when is_integer(coefficient) and coefficient >= 0 ->
          {:ok, {coefficient, value}}

        {:ok, {:ok, {coefficient, _value}}} ->
          {:error, "The coefficient must be a non-negative integer, got: #{coefficient}"}

        {:ok, :error} ->
          {:error, "The binding is not matched with the arc expression"}

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
