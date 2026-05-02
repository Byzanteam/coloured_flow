defmodule ColouredFlow.DSL.Builder do
  @moduledoc """
  `@before_compile` hook for `ColouredFlow.DSL`. Materialises the accumulated
  module attributes into a `%ColouredFlow.Definition.ColouredPetriNet{}`,
  validates it, and injects a `cpnet/0` accessor.
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColourSet.Descr
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Procedure
  alias ColouredFlow.Enactment.Marking

  alias ColouredFlow.Validators.Exceptions.MissingColourSetError
  alias ColouredFlow.Validators.Exceptions.UniqueNameViolationError

  @doc false
  defmacro __before_compile__(env) do
    cpnet = build_cpnet(env.module)
    cpnet = resolve_function_results(cpnet)
    # Compute action outputs from arc expressions, mirroring
    # `ColouredFlow.Builder.build/1`. This both populates `action.outputs`
    # and lets the arc validator allow free vars on outgoing arcs that are
    # produced by the action.
    cpnet = ColouredFlow.Builder.build(cpnet)
    initial_markings = build_initial_markings(env.module)

    case ColouredFlow.Validators.run(cpnet) do
      {:ok, validated} ->
        quote do
          @doc """
          The `%ColouredFlow.Definition.ColouredPetriNet{}` materialised from the DSL
          declarations in this module.
          """
          @spec cpnet() :: ColouredPetriNet.t()
          def cpnet, do: unquote(Macro.escape(validated))

          @doc """
          The list of `%ColouredFlow.Enactment.Marking{}` structs declared via
          `initial_marking/2`. Used by the Runner to seed an enactment; this is *not* part
          of the static CPN definition (see `cpnet/0`).
          """
          @spec initial_markings() :: [Marking.t()]
          def initial_markings, do: unquote(Macro.escape(initial_markings))

          @doc """
          The human-readable name of this workflow, or `nil` if unset.
          """
          @spec __cf_name__() :: String.t() | nil
          def __cf_name__, do: unquote(Module.get_attribute(env.module, :cf_name))

          @doc """
          The version string of this workflow, or `nil` if unset.
          """
          @spec __cf_version__() :: String.t() | nil
          def __cf_version__, do: unquote(Module.get_attribute(env.module, :cf_version))
        end

      {:error, exception} ->
        {file, line} = locate_error(exception, env)

        raise CompileError,
          description: """
          ColouredFlow.DSL: invalid workflow definition.

          #{Exception.message(exception)}
          """,
          file: file,
          line: line
    end
  end

  # Map a validator-driven error back to the originating declaration's
  # `{file, line}`. Falls back to the `defmodule` callsite when the offending
  # declaration cannot be identified.
  @spec locate_error(Exception.t(), Macro.Env.t()) :: {String.t(), non_neg_integer()}
  defp locate_error(%UniqueNameViolationError{scope: scope, name: name}, env) do
    locate_unique_violation(scope, name, env)
  end

  defp locate_error(%MissingColourSetError{colour_set: colour_set}, env) do
    locate_missing_colour_set(colour_set, env)
  end

  defp locate_error(_other, env) do
    {env.file, env.line}
  end

  # `UniqueNameValidator` halts on the *second* occurrence of a duplicate name.
  # The metadata accumulator stores entries in reverse declaration order
  # (most-recent first), so reverse to source order and pick the second
  # occurrence — that's the duplicate the validator rejected. The validator
  # uses `:variable_and_constant` to lump variables and constants together,
  # despite that not appearing in the exception's declared scope type.
  @unique_scope_attrs %{
    colour_set: [:cf_colour_sets_meta],
    place: [:cf_places_meta],
    transition: [:cf_transitions_meta],
    function: [:cf_functions_meta],
    variable_and_constant: [:cf_variables_meta, :cf_constants_meta]
  }

  defp locate_unique_violation(scope, name, env) do
    case Map.fetch(@unique_scope_attrs, scope) do
      {:ok, attrs} ->
        attrs
        |> Enum.flat_map(&source_order_meta(env.module, &1))
        |> locate_duplicate(name, env)

      :error ->
        {env.file, env.line}
    end
  end

  # `MissingColourSetError` is raised by the places/functions/variables/
  # constants validators when a referenced colour set is not declared. The
  # exception carries the missing colour set name. We probe each declaration
  # scope in the same order the validator pipeline does and return the first
  # match.
  defp locate_missing_colour_set(colour_set, env) do
    locate_missing_in_places(colour_set, env) ||
      locate_missing_in_functions(colour_set, env) ||
      locate_missing_in_constants(colour_set, env) ||
      locate_missing_in_variables(colour_set, env) ||
      {env.file, env.line}
  end

  defp locate_missing_in_places(colour_set, env) do
    env.module
    |> zip_meta(:cf_places, :cf_places_meta)
    |> Enum.find_value(fn
      {%Place{colour_set: ^colour_set}, {_name, file, line}} -> {file, line}
      _other -> nil
    end)
  end

  defp locate_missing_in_functions(colour_set, env) do
    env.module
    |> zip_meta(:cf_functions, :cf_functions_meta)
    |> Enum.find_value(fn
      {%Procedure{result: result}, {_name, file, line}} ->
        if descr_references?(result, colour_set), do: {file, line}, else: nil

      _other ->
        nil
    end)
  end

  defp locate_missing_in_constants(colour_set, env) do
    env.module
    |> zip_meta(:cf_constants, :cf_constants_meta)
    |> Enum.find_value(fn
      {%{colour_set: ^colour_set}, {_name, file, line}} -> {file, line}
      _other -> nil
    end)
  end

  defp locate_missing_in_variables(colour_set, env) do
    env.module
    |> zip_meta(:cf_variables, :cf_variables_meta)
    |> Enum.find_value(fn
      {%{colour_set: ^colour_set}, {_name, file, line}} -> {file, line}
      _other -> nil
    end)
  end

  defp zip_meta(module, items_attr, meta_attr) do
    items = source_order_meta(module, items_attr)
    metas = source_order_meta(module, meta_attr)
    Enum.zip(items, metas)
  end

  # Recursively check whether a `ColourSet.descr()` references the given
  # colour-set name as a leaf node.
  defp descr_references?({name, []}, target) when is_atom(name), do: name == target

  defp descr_references?({:tuple, types}, target) when is_list(types) do
    Enum.any?(types, &descr_references?(&1, target))
  end

  defp descr_references?({:list, type}, target), do: descr_references?(type, target)

  defp descr_references?({:map, types}, target) when is_map(types) do
    Enum.any?(types, fn {_key, type} -> descr_references?(type, target) end)
  end

  defp descr_references?({:union, types}, target) when is_map(types) do
    Enum.any?(types, fn {_tag, type} -> descr_references?(type, target) end)
  end

  defp descr_references?(_other, _target), do: false

  defp locate_duplicate(meta_list, name, env) do
    meta_list
    |> Enum.filter(fn {entry_name, _file, _line} -> entry_name == name end)
    |> case do
      [_first, {_name, file, line} | _rest] -> {file, line}
      [{_name, file, line}] -> {file, line}
      [] -> {env.file, env.line}
    end
  end

  defp source_order_meta(module, attr) do
    case Module.get_attribute(module, attr) do
      nil -> []
      list when is_list(list) -> Enum.reverse(list)
    end
  end

  @spec build_initial_markings(module()) :: [Marking.t()]
  defp build_initial_markings(module) do
    module
    |> pull(:cf_initial_markings)
    |> Enum.map(fn {place, tokens} -> %Marking{place: place, tokens: tokens} end)
  end

  @spec build_cpnet(module()) :: ColouredPetriNet.t()
  defp build_cpnet(module) do
    %ColouredPetriNet{
      colour_sets: pull(module, :cf_colour_sets),
      places: build_places(module),
      transitions: pull(module, :cf_transitions),
      arcs: pull(module, :cf_arcs),
      variables: pull(module, :cf_variables),
      constants: pull(module, :cf_constants),
      functions: pull(module, :cf_functions),
      termination_criteria: pull_one(module, :cf_termination_criteria)
    }
  end

  defp build_places(module) do
    Enum.map(pull(module, :cf_places), fn %Place{} = place -> place end)
  end

  defp pull(module, attr) do
    case Module.get_attribute(module, attr) do
      nil -> []
      list when is_list(list) -> Enum.reverse(list)
    end
  end

  # `Module.put_attribute/3` prepends in accumulate mode, so the head of the list
  # is the most recent entry. This pulls that entry. Macros that should only
  # appear once (e.g. `termination/1`) enforce uniqueness at macro-expansion
  # time, so this list will contain at most one element.
  defp pull_one(module, attr) do
    case Module.get_attribute(module, attr) do
      nil -> nil
      list when is_list(list) -> List.first(list)
      other -> other
    end
  end

  # Resolve user-defined colour-set names appearing in `Procedure.result` to
  # their underlying primitive descr. The DSL stores `{:bool, []}` when the
  # user writes `:: bool()`, which is not a valid `ColourSet.descr()`; the
  # canonical form requires the leaf to be a built-in primitive.
  @spec resolve_function_results(ColouredPetriNet.t()) :: ColouredPetriNet.t()
  defp resolve_function_results(%ColouredPetriNet{} = cpnet) do
    colour_sets = Map.new(cpnet.colour_sets, &{&1.name, &1.type})

    functions =
      Enum.map(cpnet.functions, fn %Procedure{} = procedure ->
        %{procedure | result: resolve_descr(procedure.result, colour_sets)}
      end)

    %ColouredPetriNet{cpnet | functions: functions}
  end

  @doc false
  @spec resolve_descr(ColourSet.descr(), %{ColourSet.name() => ColourSet.descr()}) ::
          ColourSet.descr()
  def resolve_descr(descr, colour_sets) do
    resolve_step(Descr.match(descr), descr, colour_sets)
  end

  @primitive_types [:integer, :float, :boolean, :binary, :unit]

  defp resolve_step({:built_in, type}, descr, _colour_sets) when type in @primitive_types,
    do: descr

  defp resolve_step({:built_in, :enum}, descr, _colour_sets), do: descr

  defp resolve_step({:built_in, :tuple}, {:tuple, types}, colour_sets) do
    {:tuple, Enum.map(types, &resolve_descr(&1, colour_sets))}
  end

  defp resolve_step({:built_in, :map}, {:map, types}, colour_sets) do
    {:map, Map.new(types, fn {key, type} -> {key, resolve_descr(type, colour_sets)} end)}
  end

  defp resolve_step({:built_in, :list}, {:list, type}, colour_sets) do
    {:list, resolve_descr(type, colour_sets)}
  end

  defp resolve_step({:built_in, :union}, {:union, types}, colour_sets) do
    {:union, Map.new(types, fn {tag, type} -> {tag, resolve_descr(type, colour_sets)} end)}
  end

  defp resolve_step({:compound, name}, descr, colour_sets) do
    case Map.fetch(colour_sets, name) do
      # Leave unresolved names alone; the validator pipeline will surface
      # the failure with a precise message.
      :error -> descr
      {:ok, underlying} -> resolve_descr(underlying, colour_sets)
    end
  end

  defp resolve_step(:unknown, descr, _colour_sets), do: descr
end
