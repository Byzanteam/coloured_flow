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

    # Storage conveniences (only useful when `:storage` is configured)
    MyWorkflow.setup_flow!()                :: term()  # inserts each call
    MyWorkflow.insert_enactment!(flow)      :: term()
    MyWorkflow.insert_enactment!(flow, [%Marking{}]) :: term()

    # Runner convenience (no `:storage` required)
    MyWorkflow.start_enactment(eid, opts)   :: DynamicSupervisor.on_start_child()

    # ColouredFlow.Runner.Enactment.Listener callbacks
    # `on_workitem_completed/4` is always emitted (it dispatches the per-transition
    # `action do ... end` bodies). The `on_enactment_*` callbacks are emitted
    # only when the matching DSL hook (`on_enactment_start`,
    # `on_enactment_terminate`, `on_enactment_exception`) is declared.
    MyWorkflow.on_workitem_completed(ctx, wi, occurrence, extras) :: :ok
    MyWorkflow.on_enactment_start(ctx, extras)             :: :ok  # if declared
    MyWorkflow.on_enactment_terminate(ctx, reason, extras) :: :ok  # if declared
    MyWorkflow.on_enactment_exception(ctx, reason, extras) :: :ok  # if declared

`cpnet/0` is the **main API**: it returns the static CPN — colour sets,
variables, places, transitions, arcs, and termination criteria — that
the runner reuses across every enactment of the workflow.

`__cpn__/1` is a **reflection helper** for declaration metadata
(modeled after `Ecto.Schema.__schema__/1`). Pass an atom key to read
the corresponding piece of workflow metadata. `:initial_markings`
returns the list of `%Marking{}` declared via `initial_marking/2`.

`setup_flow!/0`, `insert_enactment!/{1,2}` and `start_enactment/{1,2}`
are convenience wrappers over `ColouredFlow.DSL.Storage` (a thin compile-
time-fixed adapter) and `ColouredFlow.Runner.Enactment.Supervisor`. They
are *not* idempotent — every call to `setup_flow!` and
`insert_enactment!` inserts a fresh row, so application code must
deduplicate at boot if it needs that. `start_enactment` automatically
registers the workflow module as the per-instance
`ColouredFlow.Runner.Enactment.Listener`, so any `action` or
`on_enactment_*` block compiled into the module fires when the runner
crosses the matching lifecycle point. To inject per-instance
configuration, pass `listener: {__MODULE__, extras}` as an option — the
`extras` value is appended to every callback invocation as the last
positional argument and exposed inside DSL blocks as the magic binding
`extras`.

`setup_flow!/0` and `insert_enactment!/{1,2}` only work when the host
module passes `:storage` to `use ColouredFlow.DSL` (e.g.
`storage: ColouredFlow.Runner.Storage.InMemory`); without it, calling
them raises an `ArgumentError`. `start_enactment/{1,2}` is independent
of `:storage` — it only needs an enactment id (or a handle returned by
`insert_enactment!/{1,2}`) and the supervisor.

## Per-workflow options

`use ColouredFlow.DSL` accepts:

  - `:storage` — the storage module that backs `setup_flow!` /
    `insert_enactment!`. Either `ColouredFlow.Runner.Storage.Default`
    (Ecto) or `ColouredFlow.Runner.Storage.InMemory`. When omitted, the
    storage helpers raise; the rest of the DSL still compiles.
  - `:task_supervisor` — a `Task.Supervisor` registered name that wraps
    every `action do ... end` and `on_enactment_*` body. When omitted,
    bodies fall back to an unsupervised `Task.start/1` — fine for
    examples, but production code should provide a supervisor so blown
    tasks are reported and shut down with the app tree.

```elixir
use ColouredFlow.DSL,
  storage: ColouredFlow.Runner.Storage.Default,
  task_supervisor: MyApp.WorkflowTaskSup
```

## Listener dispatch

`ColouredFlow.Runner.Enactment.Listener` is the structured per-instance
counterpart to `:telemetry`. The runner still emits all telemetry
events; the listener is invoked on top of that — and is the natural
home for *workflow-specific* side effects (PubSub broadcasts, state
machines driving downstream services, etc.). Each `action do ... end`
inside a `transition` block compiles to a `__action_for__/5` clause
that the auto-generated `on_workitem_completed/4` callback dispatches
on the transition name. Inside the body, the following bindings are
available:

  - the transition's bound CPN variables (e.g. `s`, `x`)
  - `ctx` — `%{enactment_id: binary(), markings: %{place => MultiSet.t()}}`
  - `workitem` — the just-completed `%ColouredFlow.Runner.Enactment.Workitem{}`
  - `extras` — the second element of the `{module, extras}` listener tuple
    (or `nil` when the listener is a bare module)

Bodies are executed inside the configured `Task.Supervisor` so the
runner never blocks on user side effects, and any exception raised by
the listener is caught and discarded. Anything that needs to fail loudly
should fail at definition time, not runtime.

DSL macros `on_enactment_start/1`, `on_enactment_terminate/{1,2}` and
`on_enactment_exception/{1,2}` (in `ColouredFlow.DSL.Lifecycle`) compile
to the matching Listener callbacks `on_enactment_start/2`,
`on_enactment_terminate/3`, and `on_enactment_exception/3` — each
callback ends with the `extras` positional argument, which is also
exposed as a magic binding inside the macro body. Each macro may appear
at most once per workflow; a duplicate declaration is a compile-time
error.

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
