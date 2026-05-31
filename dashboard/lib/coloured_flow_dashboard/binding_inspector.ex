defmodule ColouredFlowDashboard.BindingInspector do
  @moduledoc """
  Read-only per-transition binding inspector backing the enactment detail
  Debug tab.

  Given a `%ColouredFlow.Definition.ColouredPetriNet{}` definition, the
  current `markings` map, and a transition name, enumerates every candidate
  binding the runner can compute and classifies each as one of:

    * `:enabled` — the binding satisfies the guard, every input arc
      expression evaluated cleanly AND the resulting consumption is
      included in the corresponding marking. The runner would offer this
      candidate as a workitem.
    * `:rejected_by_guard` — the binding's variables type-checked against
      the input tokens, but the transition's guard expression evaluated to
      `false` (or raised). `reason` is either a verbatim error string from
      the evaluator OR `"Guard evaluated to false"` when the guard returned
      a boolean but not `true` — the engine surfaces no error from a
      successful-but-false guard, so the inspector substitutes a fixed
      caption.
    * `:rejected_by_arc_eval` — at least one input arc's inscription failed
      to evaluate for this binding (raised, returned a non-multiset shape,
      or produced a value that does not type-check against the place's
      colour set). `reason` names the offending place and reproduces the
      evaluator message verbatim.
    * `:rejected_by_marking` — guard + every arc expression evaluated
      cleanly, but at least one input arc's consumption (after substituting
      the binding's variables) is NOT included in the place's marking. The
      offending place is named in `reason`.

  Candidate enumeration mirrors the engine exactly — the inspector does
  NOT deduplicate the combined bindings. A marking with two identical
  tokens consumed by the same arc produces TWO identical candidates, which
  is the same multiplicity `ColouredFlow.EnabledBindingElements.Computation.list/3`
  yields.

  ## Engine reuse

  The candidate enumeration mirrors `ColouredFlow.EnabledBindingElements.Computation.list/3`:

    1. Resolve every input arc's bind expressions, apply constants, match
       them against the place's marking via
       `ColouredFlow.EnabledBindingElements.Binding.match_bag/2`.
    2. Drop arc-bindings that do not type-check against their variable
       declarations (the engine calls this step `reject_invalid_bindings`).
    3. Combine compatible per-arc bindings with
       `ColouredFlow.EnabledBindingElements.Binding.combine/1` to produce
       the candidate cartesian product.

  Steps 1-3 use only public modules in the main repo (see disclosure in
  `ColouredFlowDashboardWeb.Stores.EnactmentDetailStore`'s moduledoc).
  Classification then re-uses `ColouredFlow.Expression.eval/3` for the
  guard and `ColouredFlow.MultiSet.include?/2` for the marking check. No
  runtime state is mutated.

  Pushback option (a) — see the P13 plan note. The engine returns only the
  enabled set, so to label rejections the inspector walks the candidate
  superset itself. Option (b) (a new main-repo debug surface) was
  intentionally NOT taken to preserve the epic's zero-touch guarantee.
  """

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.EnabledBindingElements.Binding
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Expression.Arc, as: ArcExpression
  alias ColouredFlow.MultiSet
  alias ColouredFlow.Runner.RuntimeCpnet

  @type guard_status() ::
          :enabled | :rejected_by_guard | :rejected_by_arc_eval | :rejected_by_marking

  @type candidate() :: %{
          binding: BindingElement.binding(),
          binding_summary: String.t(),
          guard_status: guard_status(),
          reason: String.t() | nil
        }

  @type info() :: %{
          transition: String.t(),
          candidates_count: non_neg_integer(),
          enabled_count: non_neg_integer(),
          rejected_by_guard_count: non_neg_integer(),
          rejected_by_arc_eval_count: non_neg_integer(),
          rejected_by_marking_count: non_neg_integer()
        }

  @doc """
  Returns `{:ok, info, candidates}` or `{:error, :unknown_transition}` when
  the transition name is not declared in the cpnet.

  `markings` is the runner's `%{Place.name() => Marking.t()}` map (the same
  shape carried by `Runner.Enactment.markings`).
  """
  @spec inspect(
          cpnet :: ColouredFlow.Definition.ColouredPetriNet.t(),
          markings :: %{Place.name() => Marking.t()},
          transition_name :: String.t()
        ) ::
          {:ok, info(), [candidate()]} | {:error, :unknown_transition}
  def inspect(cpnet, markings, transition_name) when is_binary(transition_name) do
    runtime_cpnet = RuntimeCpnet.from_definition(cpnet)

    case Map.fetch(runtime_cpnet.transitions, transition_name) do
      :error ->
        {:error, :unknown_transition}

      {:ok, %Transition{} = transition} ->
        candidates = enumerate(transition, runtime_cpnet, markings)
        info = roll_up(transition_name, candidates)
        {:ok, info, candidates}
    end
  end

  defp enumerate(%Transition{} = transition, %RuntimeCpnet{} = runtime_cpnet, markings) do
    inputs = arcs(transition, :p_to_t, runtime_cpnet)
    constants = runtime_cpnet.constants

    arc_bindings =
      inputs
      |> Enum.map(fn {%Arc{} = arc, %Place{} = place} ->
        marking = marking_for(place, markings)

        arc.expression.expr
        |> ArcExpression.extract_bind_exprs()
        |> Enum.map(fn arc_bind_expr ->
          consts = Map.take(constants, arc.expression.vars)
          Binding.apply_constants_to_bind_expr(arc_bind_expr, consts)
        end)
        |> Enum.flat_map(fn arc_bind_expr ->
          Binding.match_bag(marking.tokens, arc_bind_expr)
        end)
      end)
      |> reject_invalid_bindings(runtime_cpnet)

    arc_bindings
    |> Binding.combine()
    |> Enum.map(fn binding ->
      classify(binding, transition, inputs, constants, markings, runtime_cpnet)
    end)
  end

  defp classify(binding, transition, inputs, constants, markings, runtime_cpnet) do
    guard_binding = merge_constants(binding, transition, constants)

    case eval_guard(transition, guard_binding) do
      {:ok, true} ->
        case check_marking(inputs, binding, constants, markings, runtime_cpnet) do
          :ok ->
            build(binding, :enabled, nil)

          {:rejected_by_arc_eval, reason} ->
            build(binding, :rejected_by_arc_eval, reason)

          {:rejected_by_marking, reason} ->
            build(binding, :rejected_by_marking, reason)
        end

      {:ok, false} ->
        build(binding, :rejected_by_guard, "Guard evaluated to false")

      {:error, reason} ->
        build(binding, :rejected_by_guard, "Guard error: #{truncate(reason)}")
    end
  end

  defp build(binding, guard_status, reason) do
    %{
      binding: binding,
      binding_summary: format_binding(binding),
      guard_status: guard_status,
      reason: reason
    }
  end

  defp eval_guard(%Transition{guard: nil}, _binding), do: {:ok, true}

  defp eval_guard(%Transition{guard: %Expression{} = guard}, binding) do
    case ColouredFlow.Expression.eval(guard.expr, binding) do
      {:ok, bool} when is_boolean(bool) -> {:ok, bool}
      {:ok, result} -> {:error, "Guard returned non-boolean: #{inspect(result)}"}
      {:error, reason} -> {:error, format_error(reason)}
    end
  rescue
    err -> {:error, Exception.message(err)}
  end

  defp check_marking(inputs, binding, constants, markings, runtime_cpnet) do
    Enum.reduce_while(inputs, :ok, fn {%Arc{} = arc, %Place{} = place}, _acc ->
      arc_binding = merge_constants(binding, arc, constants)
      check_arc(arc, place, arc_binding, markings, runtime_cpnet)
    end)
  end

  defp check_arc(%Arc{} = arc, %Place{} = place, arc_binding, markings, runtime_cpnet) do
    with {:ok, {coefficient, value}} <- eval_arc(arc, arc_binding),
         colour_set = Map.fetch!(runtime_cpnet.colour_sets, place.colour_set),
         ctx = runtime_cpnet.of_type_context,
         {:ok, typed_value} <- ColourSet.Of.of_type(value, colour_set.type, ctx) do
      marking = marking_for(place, markings)
      tokens = MultiSet.duplicate(typed_value, coefficient)

      if MultiSet.include?(marking.tokens, tokens) do
        {:cont, :ok}
      else
        {:halt, {:rejected_by_marking, "Place #{place.name} lacks tokens for binding"}}
      end
    else
      :error ->
        {:halt, {:rejected_by_arc_eval, "Arc on place #{place.name} failed type-check"}}

      {:error, reason} ->
        {:halt,
         {:rejected_by_arc_eval,
          "Arc on place #{place.name} failed to evaluate: #{truncate(reason)}"}}
    end
  end

  defp eval_arc(%Arc{} = arc, binding) do
    case ColouredFlow.Expression.eval(arc.expression.expr, binding) do
      {:ok, {:ok, {coefficient, value}}} when is_integer(coefficient) and coefficient >= 0 ->
        {:ok, {coefficient, value}}

      {:ok, {:ok, {coefficient, _value}}} ->
        {:error, "Non-negative coefficient required, got #{inspect(coefficient)}"}

      {:ok, :error} ->
        {:error, "Binding does not match arc expression"}

      {:ok, result} ->
        {:error, "Arc expression must return a MultiSet pair, got #{inspect(result)}"}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  rescue
    err -> {:error, Exception.message(err)}
  end

  # The engine's `Computation.reject_invalid_bandings/2` is private. Inline a
  # minimal copy here so the inspector keeps zero main-repo coupling beyond
  # documented public modules.
  defp reject_invalid_bindings(bindings_list, %RuntimeCpnet{} = runtime_cpnet) do
    ctx = runtime_cpnet.of_type_context

    Enum.map(bindings_list, fn arc_bindings ->
      Enum.filter(arc_bindings, &valid_binding?(&1, runtime_cpnet, ctx))
    end)
  end

  defp valid_binding?(binding, runtime_cpnet, ctx) do
    Enum.all?(binding, fn {name, value} -> valid_pair?(name, value, runtime_cpnet, ctx) end)
  end

  defp valid_pair?(name, value, runtime_cpnet, ctx) do
    case Map.fetch(runtime_cpnet.variables, name) do
      {:ok, variable} ->
        match?({:ok, _typed}, ColourSet.Of.of_type(value, {variable.colour_set, []}, ctx))

      :error ->
        false
    end
  end

  defp arcs(%Transition{name: name}, orientation, %RuntimeCpnet{} = runtime_cpnet) do
    Map.get(runtime_cpnet.arcs_by_transition_orientation, {name, orientation}, [])
  end

  defp marking_for(%Place{name: name}, markings) do
    Map.get(markings, name, %Marking{place: name, tokens: MultiSet.new()})
  end

  defp merge_constants(binding, %Arc{expression: %Expression{vars: vars}}, constants) do
    consts = constants |> Map.take(vars) |> Enum.to_list()
    Keyword.merge(consts, binding)
  end

  defp merge_constants(binding, %Transition{guard: %Expression{vars: vars}}, constants) do
    consts = constants |> Map.take(vars) |> Enum.to_list()
    Keyword.merge(binding, consts)
  end

  defp merge_constants(binding, %Transition{}, _constants), do: binding

  defp roll_up(transition_name, candidates) do
    by_status = Enum.frequencies_by(candidates, & &1.guard_status)

    %{
      transition: transition_name,
      candidates_count: length(candidates),
      enabled_count: Map.get(by_status, :enabled, 0),
      rejected_by_guard_count: Map.get(by_status, :rejected_by_guard, 0),
      rejected_by_arc_eval_count: Map.get(by_status, :rejected_by_arc_eval, 0),
      rejected_by_marking_count: Map.get(by_status, :rejected_by_marking, 0)
    }
  end

  defp format_binding(binding) when is_list(binding) do
    Enum.map_join(binding, ", ", fn {name, value} -> "#{name} = #{inspect(value)}" end)
  end

  defp format_binding(_other), do: ""

  defp format_error([%{__exception__: true} = exception | _rest]),
    do: Exception.message(exception)

  defp format_error(reason), do: inspect(reason, limit: 50, printable_limit: 200)

  defp truncate(string, limit \\ 120) when is_binary(string) do
    if byte_size(string) > limit do
      binary_part(string, 0, limit) <> "…"
    else
      string
    end
  end
end
