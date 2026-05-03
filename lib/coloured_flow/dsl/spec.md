A declarative Elixir DSL for defining Coloured Petri Nets.

This is the high-level workflow-assembly layer on top of
`ColouredFlow.Notation.*`. The DSL composes colour sets, variables,
constants, places, transitions, arcs, functions, and termination criteria
into a complete `ColouredFlow.Definition.ColouredPetriNet` and validates
it at compile time. Any issue raises during `mix compile`, never at
runtime.

## Synopsis

    defmodule MyWorkflow do
      use ColouredFlow.DSL

      name "My Workflow"
      version "1.0.0"

      colset int() :: integer()
      colset bool() :: boolean()

      var x :: int()
      val pi :: float() = 3.14

      function is_even(x) :: bool() do
        Integer.mod(x, 2) === 0
      end

      place :input, :int
      place :output, :int

      initial_marking :input, ~MS[1 2 3]

      transition :pass_through do
        guard x > 0

        input :input, bind({1, x}), label: "in"

        output :output do
          if is_even(x), do: {1, x}, else: {1, x + 1}
        end
      end

      termination do
        on_markings do
          match?(
            %{"output" => out_ms} when multi_set_coefficient(out_ms, 1) >= 5,
            markings
          )
        end
      end
    end

## Generated module surface

A module that uses `ColouredFlow.DSL` exposes:

    MyWorkflow.cpnet()                      :: %ColouredFlow.Definition.ColouredPetriNet{}
    MyWorkflow.__cpn__(:name)               :: String.t() | nil
    MyWorkflow.__cpn__(:version)            :: String.t() | nil
    MyWorkflow.__cpn__(:initial_markings)   :: [%ColouredFlow.Enactment.Marking{}]

    # Runner conveniences
    MyWorkflow.insert_enactment(flow_id)                     :: {:ok, %Schemas.Enactment{}}
    MyWorkflow.insert_enactment(flow_id, [%Marking{}])       :: {:ok, %Schemas.Enactment{}}
    MyWorkflow.insert_enactment(flow_id, [%Marking{}], opts) :: {:ok, %Schemas.Enactment{}}
    MyWorkflow.start_enactment(enactment_id, opts)           :: DynamicSupervisor.on_start_child()

    # ColouredFlow.Runner.Enactment.LifecycleHooks callbacks
    # `on_workitem_completed/2` is always emitted (it dispatches the per-transition
    # `action do ... end` bodies). The `on_enactment_*` callbacks are emitted
    # only when the matching DSL hook (`on_enactment_start`,
    # `on_enactment_terminate`, `on_enactment_exception`) is declared.
    MyWorkflow.on_workitem_completed(event, options)  :: :ok
    MyWorkflow.on_enactment_start(event, options)     :: :ok  # if declared
    MyWorkflow.on_enactment_terminate(event, options) :: :ok  # if declared
    MyWorkflow.on_enactment_exception(event, options) :: :ok  # if declared

`cpnet/0` is the **main API**: it returns the static CPN — colour sets,
variables, places, transitions, arcs, and termination criteria — that
the runner reuses across every enactment of the workflow.

`__cpn__/1` is a **reflection helper** for declaration metadata
(modeled after `Ecto.Schema.__schema__/1`). Pass an atom key to read
the corresponding piece of workflow metadata. `:initial_markings`
returns the list of `%Marking{}` declared via `initial_marking/2`.

`insert_enactment/3` is a thin convenience wrapper over
`ColouredFlow.Runner.Storage.insert_enactment/1`. It is not idempotent
— each call inserts a fresh row, so application code must deduplicate
at boot if it needs that. The flow row itself must already exist; the
DSL no longer ships a flow-insertion helper, so callers insert flows
directly via the storage primitives (e.g.,
`%Schemas.Flow{} |> Ecto.Changeset.cast(...) |> Repo.insert!()` for
the `Default` backend, or `Storage.InMemory.insert_flow!/1` for
`InMemory`).

`start_enactment/2` registers the workflow module as the per-instance
`ColouredFlow.Runner.Enactment.LifecycleHooks`, so any `action` or
`on_enactment_*` block compiled into the module fires when the runner
crosses the matching lifecycle point. To inject per-instance
configuration, pass `lifecycle_hooks: {__MODULE__, options}` — the
`options` keyword list is forwarded to every callback invocation as
the second argument and exposed inside DSL blocks as the magic
binding `options`. To disable hooks for one enactment, pass
`lifecycle_hooks: nil`.

## Per-workflow options

`use ColouredFlow.DSL` accepts:

  - `:task_supervisor` — a `Task.Supervisor` registered name that wraps
    every `action do ... end` and `on_enactment_*` body. When omitted,
    bodies fall back to an unsupervised `Task.start/1` — fine for
    examples, but production code should provide a supervisor so blown
    tasks are reported and shut down with the app tree.

```elixir
use ColouredFlow.DSL,
  task_supervisor: MyApp.WorkflowTaskSup
```

## Lifecycle hook dispatch

`ColouredFlow.Runner.Enactment.LifecycleHooks` is the structured
per-instance counterpart to `:telemetry`. The runner still emits all
telemetry events; the hooks are invoked on top of that — and are the
natural home for *workflow-specific* side effects (PubSub broadcasts,
state machines driving downstream services, etc.). Each
`action do ... end` inside a `transition` block compiles to a
`__action_for__/3` clause that the auto-generated
`on_workitem_completed/2` callback dispatches on the transition name.
Inside the body, the following bindings are available:

  - the transition's bound CPN variables (e.g. `s`, `x`), plucked from
    `event.binding`
  - `event` — `%{enactment_id, markings, workitem, occurrence, binding}`
    for the completed-workitem event
  - `options` — the keyword list registered alongside the hook module
    via the `{module, options}` tuple form (or `[]` when registered as
    a bare module)

Bodies are executed inside the configured `Task.Supervisor` so the
runner never blocks on user side effects, and any exception raised by
the hook is caught and discarded. Anything that needs to fail loudly
should fail at definition time, not runtime.

DSL macros `on_enactment_start/1`, `on_enactment_terminate/1`, and
`on_enactment_exception/1` (in `ColouredFlow.DSL.Lifecycle`) compile to
the matching `LifecycleHooks` callbacks `on_enactment_start/2`,
`on_enactment_terminate/2`, and `on_enactment_exception/2`. Each event
map carries the relevant payload (e.g., `event.reason` for
terminate/exception); the `options` keyword is exposed as a magic
binding inside the macro body. Each macro may appear at most once per
workflow; a duplicate declaration is a compile-time error.

## Universal expression rule

Every macro that accepts an expression follows the same shape:

  - **Single-line**: the expression is the last positional argument.
  - **Multi-line**: pass a `do ... end` block; the block body **is** the
    expression. There is no `expr do ... end` wrapper.
  - **Options** (e.g., `label:`): keyword arguments only, before the `do`
    block.

```elixir
guard x > 0                                 # single-line
guard do x > 0 and y > 0 end                # multi-line

input :p, bind({1, x})                      # single-line, no label
input :p, bind({1, x}), label: "in"         # single-line, with label

input :p, label: "in" do                    # multi-line, with label
  if x > 0, do: bind({1, x}), else: bind({2, x})
end
```

## Top-level macros

### `name/1`

Set the human-readable workflow name.

    name "Traffic Light"

### `version/1`

Set the workflow version (free-form string; semver is conventional).

    version "1.0.0"

### `colset/1`

Re-exported from `ColouredFlow.Notation.Colset`. Declares a colour set.

    colset int()    :: integer()
    colset bool()   :: boolean()
    colset status() :: ok | err
    colset point()  :: {integer(), integer()}

### `var/1`

Re-exported from `ColouredFlow.Notation.Var`. Declares a variable bound
to a colour set.

    var x :: int()

### `val/1`

Re-exported from `ColouredFlow.Notation.Val`. Declares a constant bound
to a colour set.

    val pi :: float() = 3.14

### `place/2`

Declare a place. Place names are atoms; the underlying `%Place{}` stores
them as strings. The colour set name is also an atom and must be a
declared `colset`.

    place :input, :int
    place :output, :int

### `initial_marking/2`

Declare an initial marking for a place. Multiple `initial_marking/2`
calls accumulate in declaration order and are exposed via
`__cpn__(:initial_markings)` on the host module. The cpnet definition
itself is not affected.

    initial_marking :input, ~MS[1 2 3]

### `function/1` and `function/2`

Declare a user-defined function (CPN procedure) usable in arc, guard,
action, and termination expressions. Arguments listed in the head must
appear as free variables in the body; the result type after `::` is the
result colour set.

    function is_even(x) :: bool(), do: Integer.mod(x, 2) === 0

    function double(x) :: int() do
      x * 2
    end

### `transition/2`

Declare a transition. The block accepts `guard/1`, `action/1`,
`input/2,3`, and `output/2,3`.

    transition :pass_through do
      guard x > 0

      input :input, bind({1, x})
      output :output, {1, x * 2}

      action do
        :ok
      end
    end

### `termination/1`

Declare termination criteria. The block accepts criterion-specific
sub-macros. Currently `on_markings/1` is the only kind. Future kinds
(`on_time`, `on_workitem_count`, …) plug in here without changing call
sites.

    termination do
      on_markings do
        match?(
          %{"output" => out_ms} when multi_set_coefficient(out_ms, 1) >= 5,
          markings
        )
      end
    end

## Transition-scope macros

### `guard/1`

A boolean expression over bound variables. Optional. A falsy result
disables the transition for the current binding. Declaring `guard` more
than once in a transition is a compile-time error.

    guard x > 0
    guard do
      x > 0 and is_even(x)
    end

### `action/1`

Expression evaluated when the transition fires. Optional. Use it to
provide bindings for outgoing arcs that reference variables not bound by
any incoming arc. Declaring `action` more than once in a transition is a
compile-time error.

    action :ok
    action do
      log("fired")
      :ok
    end

### `input/2` and `input/3`

Declare an incoming arc (place → transition). The expression must use
`bind/1` to consume tokens. Options: `:label`.

    input :input, bind({1, x})
    input :input, bind({1, x}), label: "in"
    input :input, label: "in" do
      if x > 0, do: bind({1, x}), else: bind({2, x})
    end

### `output/2` and `output/3`

Declare an outgoing arc (transition → place). The expression evaluates
to the multiset of tokens produced. Options: `:label`.

    output :output, {1, x}
    output :output, {1, x}, label: "out"
    output :output, label: "out" do
      if x > 0, do: {1, x}, else: {0, x}
    end

## Termination-scope macros

### `on_markings/1`

Boolean expression over the special variable `markings` — a map of place
name (string) to token multiset. A truthy result terminates the
enactment with reason `:explicit`. Declaring `on_markings` more than
once is a compile-time error.

    on_markings do
      match?(
        %{"output" => out_ms} when multi_set_coefficient(out_ms, 1) >= 5,
        markings
      )
    end

## Compile-time validation

The `@before_compile` hook builds a `%ColouredPetriNet{}` from the
accumulated declarations, runs `ColouredFlow.Builder.build/1` (which
populates `action.outputs` from arc/guard analysis), and runs
`ColouredFlow.Validators.run/1`:

  - colour set declarations are well-formed,
  - place / variable / constant colour-set references resolve,
  - arc endpoints exist,
  - incoming arcs use `bind/1`,
  - free variables in expressions resolve to `var/1` (or function args),
  - guard variables are bound by the same transition's incoming arcs,
  - function names are unique and result descrs are fully resolved,
  - termination criteria reference only `markings`.

Any failure raises a `CompileError`. Duplicate-name and missing-colour-set
violations point back to the originating declaration via
`{file, line}` metadata captured at macro expansion; other validator
errors fall back to the `defmodule` callsite.
