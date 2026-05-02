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

  @doc false
  defmacro __before_compile__(env) do
    cpnet = build_cpnet(env.module)
    cpnet = resolve_function_results(cpnet)
    # Compute action outputs from arc expressions, mirroring
    # `ColouredFlow.Builder.build/1`. This both populates `action.outputs`
    # and lets the arc validator allow free vars on outgoing arcs that are
    # produced by the action.
    cpnet = ColouredFlow.Builder.build(cpnet)

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
        raise CompileError,
          description: """
          ColouredFlow.DSL: invalid workflow definition.

          #{Exception.message(exception)}
          """,
          file: env.file,
          line: env.line
    end
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

  defp pull_one(module, attr) do
    case Module.get_attribute(module, attr) do
      nil -> nil
      list when is_list(list) -> List.last(list)
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
