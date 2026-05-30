defmodule ColouredFlowDashboard.OutputSchemaBuilder do
  @moduledoc """
  Resolves the schema for a transition's free-variable outputs.

  Walks `Action.outputs` (auto-populated by
  `ColouredFlow.Builder.SetActionOutputs` as
  `output_arc_vars MINUS input_arc_vars MINUS constants`), pairs each free
  variable with its declared colour set, and reduces the colour-set descriptor
  to one of the wire kinds documented on
  `ColouredFlowDashboardWeb.Views.OutputVar`.

  Reuses the cached `%ColouredPetriNet{}` returned by
  `ColouredFlowDashboard.TelemetryBridge.lookup_cpnet/2`; never queries
  storage itself.
  """

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable
  alias ColouredFlowDashboardWeb.Views.OutputVar

  @type kind() :: :string | :integer | :boolean | :enum | :json

  @doc """
  Returns the ordered schema for a transition's free variables.

  Empty list when the transition is unknown to the cpnet OR the cpnet is
  `nil` (cache miss). Order matches `Action.outputs` so the SPA renders the
  controls in the same order the DSL author declared them.
  """
  @spec build(ColouredPetriNet.t() | nil, String.t()) :: [OutputVar.t()]
  def build(nil, _transition_name), do: []

  def build(%ColouredPetriNet{} = cpnet, transition_name)
      when is_binary(transition_name) do
    case find_transition(cpnet, transition_name) do
      %Transition{action: %{outputs: outputs}} ->
        variables = Map.new(cpnet.variables, &{&1.name, &1})
        colour_sets = Map.new(cpnet.colour_sets, &{&1.name, &1.type})

        Enum.map(outputs, &resolve_var(&1, variables, colour_sets))

      _missing ->
        []
    end
  end

  defp find_transition(%ColouredPetriNet{transitions: transitions}, name) do
    Enum.find(transitions, fn %Transition{name: tname} -> tname == name end)
  end

  defp resolve_var(var_name, variables, colour_sets) when is_atom(var_name) do
    case Map.fetch(variables, var_name) do
      {:ok, %Variable{colour_set: cs_name}} ->
        descr = Map.get(colour_sets, cs_name)
        {kind, enum_values, hint} = classify(descr, cs_name, colour_sets)

        %OutputVar{
          name: Atom.to_string(var_name),
          colour_set: Atom.to_string(cs_name),
          kind: kind,
          enum_values: enum_values,
          hint: hint
        }

      :error ->
        %OutputVar{
          name: Atom.to_string(var_name),
          colour_set: "",
          kind: :json,
          enum_values: nil,
          hint: "Variable not declared in cpnet; provide JSON."
        }
    end
  end

  defp classify(descr, cs_name, colour_sets) do
    case resolve_descr(descr, colour_sets, 0) do
      {:integer, []} -> {:integer, nil, nil}
      {:binary, []} -> {:string, nil, nil}
      {:boolean, []} -> {:boolean, nil, nil}
      {:enum, atoms} -> {:enum, Enum.map(atoms, &Atom.to_string/1), nil}
      _other -> {:json, nil, complex_hint(cs_name)}
    end
  end

  # Hop through colour-set aliases (e.g. `colset verdict_t() :: binary()` ->
  # `{:verdict_t, []}` -> `{:binary, []}`). Bounded at 16 hops as a paranoia
  # guard against pathological cycles even though the cpnet validator already
  # rejects them.
  defp resolve_descr(descr, _colour_sets, depth) when depth >= 16, do: descr

  defp resolve_descr({atom, []} = descr, colour_sets, depth) when is_atom(atom) do
    case Map.fetch(colour_sets, atom) do
      {:ok, inner} when inner != descr -> resolve_descr(inner, colour_sets, depth + 1)
      _miss -> descr
    end
  end

  defp resolve_descr(other, _colour_sets, _depth), do: other

  defp complex_hint(cs_name) when is_atom(cs_name),
    do: "Colour set `#{cs_name}` is complex; provide JSON."

  @doc """
  Coerce a single SPA-supplied value into the runner-shaped term for the
  given output variable schema.

  Used by `:complete_workitem` to round-trip primitive types from JSON wire
  values back to Elixir terms:

    * `:string`  — accepts a binary verbatim.
    * `:integer` — accepts an Elixir integer (the SPA's `Input` type=number
      produces JS numbers; the JSON decoder yields integers when no
      fractional part is present).
    * `:boolean` — accepts `true`/`false`.
    * `:enum`    — accepts a binary matching one of `enum_values`; coerces
      to the corresponding atom via `String.to_existing_atom/1` (the cpnet
      already loaded these atoms when the colset declaration evaluated, so
      they exist on the BEAM).
    * `:json`    — passes the value through unchanged.

  Returns `{:ok, term}` or `{:error, reason}` where `reason` is one of:

    * `{:type_mismatch, expected_kind_string}` — wrong wire shape.
    * `{:unknown_enum, value}` — enum value not in `enum_values`.
  """
  @spec coerce_value(OutputVar.t() | nil, term()) ::
          {:ok, term()} | {:error, term()}
  def coerce_value(nil, value), do: {:ok, value}

  def coerce_value(%OutputVar{kind: :json}, value), do: {:ok, value}

  def coerce_value(%OutputVar{kind: :string}, value) when is_binary(value),
    do: {:ok, value}

  def coerce_value(%OutputVar{kind: :string}, _value),
    do: {:error, {:type_mismatch, "string"}}

  def coerce_value(%OutputVar{kind: :integer}, value) when is_integer(value),
    do: {:ok, value}

  def coerce_value(%OutputVar{kind: :integer}, _value),
    do: {:error, {:type_mismatch, "integer"}}

  def coerce_value(%OutputVar{kind: :boolean}, value) when is_boolean(value),
    do: {:ok, value}

  def coerce_value(%OutputVar{kind: :boolean}, _value),
    do: {:error, {:type_mismatch, "boolean"}}

  def coerce_value(%OutputVar{kind: :enum, enum_values: values}, value)
      when is_binary(value) and is_list(values) do
    if value in values do
      {:ok, String.to_existing_atom(value)}
    else
      {:error, {:unknown_enum, value}}
    end
  rescue
    ArgumentError -> {:error, {:unknown_enum, value}}
  end

  def coerce_value(%OutputVar{kind: :enum}, _value),
    do: {:error, {:type_mismatch, "enum"}}
end
