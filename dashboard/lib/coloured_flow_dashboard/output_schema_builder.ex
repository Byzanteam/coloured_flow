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

  @type kind() :: :string | :integer | :boolean | :enum | :elixir

  @doc """
  Returns the ordered schema for a transition's free variables.

  Empty list when the transition is unknown to the cpnet OR the cpnet is
  `nil` (cache miss). Order matches `Action.outputs`, which
  `ColouredFlow.Builder.SetActionOutputs` sorts alphabetically post-build —
  so the SPA renders the controls in alphabetical order, not DSL declaration
  order.
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
        example = if kind == :elixir, do: example_literal_for(descr, colour_sets)

        %OutputVar{
          name: Atom.to_string(var_name),
          colour_set: Atom.to_string(cs_name),
          kind: kind,
          enum_values: enum_values,
          hint: hint,
          example: example
        }

      :error ->
        %OutputVar{
          name: Atom.to_string(var_name),
          colour_set: "",
          kind: :elixir,
          enum_values: nil,
          hint: "Variable not declared in cpnet; provide an Elixir term literal.",
          example: ":your_term"
        }
    end
  end

  defp example_literal_for(nil, _colour_sets), do: ":your_term"

  defp example_literal_for(descr, colour_sets) do
    descr |> resolve_descr(colour_sets, 0) |> example_literal(colour_sets)
  end

  defp classify(descr, cs_name, colour_sets) do
    case resolve_descr(descr, colour_sets, 0) do
      {:integer, []} -> {:integer, nil, nil}
      {:binary, []} -> {:string, nil, nil}
      {:boolean, []} -> {:boolean, nil, nil}
      {:enum, atoms} -> {:enum, Enum.map(atoms, &Atom.to_string/1), nil}
      _other -> {:elixir, nil, complex_hint(cs_name)}
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
    do: "Colour set `#{cs_name}` is complex; provide an Elixir term literal."

  @doc """
  Returns a short example literal (as a string) suitable for the SPA textarea
  placeholder. Resolves through compound colour-set aliases the same way
  `classify/3` does, then renders the resolved descriptor as an Elixir literal:

    * `{:integer, []}` → `"0"`
    * `{:float, []}`   → `"0.0"`
    * `{:binary, []}`  → `"\\"text\\""`
    * `{:boolean, []}` → `"true"`
    * `{:unit, []}`    → `"{}"`
    * `{:tuple, types}` → `"{<example_for_type_1>, ...}"`
    * `{:map, types}`  → `"%{key: <example>}"`
    * `{:enum, atoms}` → `":first_atom"`
    * `{:union, types}` → `"{:tag, <example>}"` (first variant)
    * `{:list, type}`  → `"[<example>]"`
    * unknown / cache miss → `":your_term"`

  Falls back to `":your_term"` when the cpnet is `nil` or the variable is not
  declared.
  """
  @spec example(ColouredPetriNet.t() | nil, String.t() | atom()) :: String.t()
  def example(nil, _var_name), do: ":your_term"

  def example(%ColouredPetriNet{} = cpnet, var_name) when is_binary(var_name) do
    example(cpnet, String.to_existing_atom(var_name))
  rescue
    ArgumentError -> ":your_term"
  end

  def example(%ColouredPetriNet{} = cpnet, var_name) when is_atom(var_name) do
    variables = Map.new(cpnet.variables, &{&1.name, &1})
    colour_sets = Map.new(cpnet.colour_sets, &{&1.name, &1.type})

    with {:ok, %Variable{colour_set: cs_name}} <- Map.fetch(variables, var_name),
         descr = Map.get(colour_sets, cs_name),
         true <- is_tuple(descr) do
      descr |> resolve_descr(colour_sets, 0) |> example_literal(colour_sets)
    else
      _miss -> ":your_term"
    end
  end

  @doc """
  Like `example/2` but resolves directly from a colour-set descriptor. Used by
  the inline `:elixir` placeholder when only the descriptor is on hand.
  """
  @spec example_for_descr(ColouredFlow.Definition.ColourSet.descr() | nil) :: String.t()
  def example_for_descr(nil), do: ":your_term"
  def example_for_descr(descr), do: example_literal(descr, %{})

  # Render a resolved descriptor as an Elixir literal source string. The
  # `colour_sets` map is used to recurse through nested compound aliases for
  # tuple/list/map element types; resolution depth is bounded by
  # `resolve_descr/3` (max 16 hops).
  defp example_literal({:integer, []}, _cs), do: "0"
  defp example_literal({:float, []}, _cs), do: "0.0"
  defp example_literal({:binary, []}, _cs), do: ~s("text")
  defp example_literal({:boolean, []}, _cs), do: "true"
  defp example_literal({:unit, []}, _cs), do: "{}"

  defp example_literal({:enum, [first | _rest]}, _cs) when is_atom(first),
    do: inspect(first)

  defp example_literal({:tuple, types}, cs) when is_list(types) do
    "{" <> Enum.map_join(types, ", ", &nested_example(&1, cs)) <> "}"
  end

  defp example_literal({:list, inner}, cs) do
    "[" <> nested_example(inner, cs) <> "]"
  end

  defp example_literal({:map, types}, cs) when is_map(types) do
    case Map.to_list(types) do
      [] ->
        "%{}"

      pairs ->
        body =
          Enum.map_join(pairs, ", ", fn {key, type} ->
            "#{key}: #{nested_example(type, cs)}"
          end)

        "%{" <> body <> "}"
    end
  end

  defp example_literal({:union, types}, cs) when is_map(types) do
    case Map.to_list(types) do
      [{tag, inner} | _rest] -> "{#{inspect(tag)}, #{nested_example(inner, cs)}}"
      [] -> ":your_term"
    end
  end

  defp example_literal(_other, _cs), do: ":your_term"

  defp nested_example(descr, cs), do: descr |> resolve_descr(cs, 0) |> example_literal(cs)

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
    * `:elixir`  — accepts a binary holding an Elixir term literal (atoms,
      integers, floats, booleans, nil, binaries, tuples, lists, keyword
      lists). Parsed with `Code.string_to_quoted/2` and validated against a
      literal-only walker (no function calls, variables, or sigils).

  Returns `{:ok, term}` or `{:error, reason}` where `reason` is one of:

    * `{:type_mismatch, expected_kind_string}` — wrong wire shape.
    * `{:unknown_enum, value}` — enum value not in `enum_values`.
    * `{:invalid_elixir, message}` — `:elixir` text rejected by the parser
      or the literal walker; `message` is operator-facing.
  """
  @spec coerce_value(OutputVar.t() | nil, term()) ::
          {:ok, term()} | {:error, term()}
  def coerce_value(nil, value), do: {:ok, value}

  def coerce_value(%OutputVar{kind: :elixir}, value) when is_binary(value) do
    ColouredFlowDashboard.ElixirTermDecoder.decode(value)
  end

  def coerce_value(%OutputVar{kind: :elixir}, _value),
    do: {:error, {:type_mismatch, "elixir"}}

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
