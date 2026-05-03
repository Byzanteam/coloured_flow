defmodule ColouredFlow.DSL do
  @external_resource Path.expand("dsl/spec.md", __DIR__)

  @moduledoc File.read!(@external_resource)

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Variable

  @doc false
  defmacro __using__(opts) do
    storage = Keyword.get(opts, :storage)
    task_supervisor = Keyword.get(opts, :task_supervisor)

    quote do
      import ColouredFlow.DSL,
        only: [
          name: 1,
          version: 1,
          colset: 1,
          var: 1,
          val: 1
        ]

      import ColouredFlow.DSL.Place,
        only: [
          place: 2,
          initial_marking: 2
        ]

      import ColouredFlow.DSL.Function,
        only: [
          function: 1,
          function: 2
        ]

      import ColouredFlow.DSL.Transition,
        only: [
          transition: 2,
          guard: 1,
          action: 1
        ]

      import ColouredFlow.DSL.Arc,
        only: [
          input: 2,
          input: 3,
          output: 2,
          output: 3
        ]

      import ColouredFlow.DSL.Termination,
        only: [
          termination: 1,
          on_markings: 1
        ]

      import ColouredFlow.DSL.Lifecycle,
        only: [
          on_enactment_start: 1,
          on_enactment_terminate: 1,
          on_enactment_terminate: 2,
          on_enactment_exception: 1,
          on_enactment_exception: 2
        ]

      import ColouredFlow.MultiSet, only: [sigil_MS: 2, multi_set_coefficient: 2]

      Module.register_attribute(__MODULE__, :cf_colour_sets, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_variables, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_constants, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_functions, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_places, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_initial_markings, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_transitions, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_arcs, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_termination_criteria, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_name, accumulate: false)
      Module.register_attribute(__MODULE__, :cf_version, accumulate: false)
      Module.register_attribute(__MODULE__, :cf_storage, accumulate: false)
      Module.register_attribute(__MODULE__, :cf_task_supervisor, accumulate: false)

      # Per-declaration metadata: accumulates `{name, file, line}` triples so
      # `Builder` can map validator-driven errors back to the offending callsite.
      Module.register_attribute(__MODULE__, :cf_colour_sets_meta, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_variables_meta, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_constants_meta, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_functions_meta, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_places_meta, accumulate: true)
      Module.register_attribute(__MODULE__, :cf_transitions_meta, accumulate: true)

      # Per-transition action body AST collected by `transition do ... end` —
      # each entry is `{transition_name, body_ast, free_vars}`.
      Module.register_attribute(__MODULE__, :cf_transition_actions, accumulate: true)

      # Enactment-level lifecycle hook bodies (`{kind, body_ast}`).
      Module.register_attribute(__MODULE__, :cf_lifecycle_hooks, accumulate: true)

      @cf_storage unquote(storage)
      @cf_task_supervisor unquote(task_supervisor)

      @before_compile ColouredFlow.DSL.Builder
    end
  end

  @doc """
  Set the human-readable workflow name. Compile-time only.

  ## Examples

      name "Traffic Light"
  """
  defmacro name(value) do
    quote do
      @cf_name unquote(value)
    end
  end

  @doc """
  Set the workflow version (any string the caller chooses; semver is
  conventional).

  ## Examples

      version "1.0.0"
  """
  defmacro version(value) do
    quote do
      @cf_version unquote(value)
    end
  end

  @doc """
  Re-exported from `ColouredFlow.Notation.Colset`. Declares a colour set.

  ## Examples

      colset int()    :: integer()
      colset bool()   :: boolean()
      colset status() :: ok | err
      colset point()  :: {integer(), integer()}
  """
  defmacro colset(declaration) do
    {name, type} = ColouredFlow.Notation.Colset.__colset__(declaration)
    caller_file = __CALLER__.file
    caller_line = __CALLER__.line

    quote do
      @cf_colour_sets %ColourSet{
        name: unquote(name),
        type: unquote(type)
      }
      @cf_colour_sets_meta {unquote(name), unquote(caller_file), unquote(caller_line)}
    end
  end

  @doc """
  Re-exported from `ColouredFlow.Notation.Var`. Declares a variable bound to a
  colour set.

  ## Examples

      var x :: int()
  """
  defmacro var(declaration) do
    {name, colour_set} = ColouredFlow.Notation.Var.__var__(declaration)
    caller_file = __CALLER__.file
    caller_line = __CALLER__.line

    quote do
      @cf_variables %Variable{
        name: unquote(name),
        colour_set: unquote(colour_set)
      }
      @cf_variables_meta {unquote(name), unquote(caller_file), unquote(caller_line)}
    end
  end

  @doc """
  Re-exported from `ColouredFlow.Notation.Val`. Declares a constant bound to a
  colour set.

  ## Examples

      val pi :: float() = 3.14
  """
  defmacro val(declaration) do
    {name, colour_set, value} = ColouredFlow.Notation.Val.__val__(declaration)
    caller_file = __CALLER__.file
    caller_line = __CALLER__.line

    quote do
      @cf_constants %Constant{
        name: unquote(name),
        colour_set: unquote(colour_set),
        value: unquote(value)
      }
      @cf_constants_meta {unquote(name), unquote(caller_file), unquote(caller_line)}
    end
  end
end
