A declarative Elixir DSL for defining Coloured Petri Nets.

This is the high-level workflow-assembly layer. The low-level building
blocks (`colset/1`, `var/1`, `val/1`) live in `ColouredFlow.Notation.*` and
are reused here. The DSL composes them into a complete
`ColouredFlow.Definition.ColouredPetriNet` and validates it at compile
time.

## Synopsis

    defmodule MyWorkflow do
      use ColouredFlow.DSL

      name "My Workflow"
      version "1.0.0"

      # types
      colset int() :: integer()
      colset bool() :: boolean()

      # bindings
      var x :: int()
      var y :: int()
      val pi :: float() = 3.14

      # functions
      function is_even(x) :: bool() do
        Integer.mod(x, 2) === 0
      end

      # graph
      place :input, :int
      place :output, :int

      initial_marking :input, ~MS[1, 2, 3]

      transition :pass_through do
        guard x > 0

        input :input, bind({1, x}), label: "in"

        output :output do
          if is_even(x), do: {1, x}, else: {1, x + 1}
        end

        action do
          log("fired with x=\#{x}")
        end
      end

      # termination
      termination do
        on_markings do
          match?(
            %{"output" => out_ms} when multi_set_coefficient(out_ms, 1) >= 5,
            markings
          )
        end
      end
    end

    MyWorkflow.cpnet() #=> %ColouredFlow.Definition.ColouredPetriNet{...}

## Module surface

`use ColouredFlow.DSL` injects the macros listed below and registers an
`@before_compile` hook that assembles a
`%ColouredFlow.Definition.ColouredPetriNet{}` from the accumulated
declarations and runs `ColouredFlow.Validators.run/1` against it. Any
validator failure raises at compile time so misconfigured workflows never
reach runtime.

Compiled modules expose a single zero-arity helper:

    MyWorkflow.cpnet() :: %ColouredFlow.Definition.ColouredPetriNet{}

Higher-level integration (running an enactment, persisting it, etc.) is
intentionally left to the existing `ColouredFlow.Runner.*` API. The DSL
produces only the static definition.

## Universal expression rule

Every macro that accepts an expression follows the same rule:

- **Single-line**: the expression is the last positional argument.
- **Multi-line**: pass a `do ... end` block; the block body **is** the
  expression. There is no `expr do ... end` wrapper anywhere.
- **Options** (e.g., `label:`): keyword arguments only, placed before the
  `do` block.

```elixir
guard x > 0                                  # single-line
guard do x > 0 and y > 0 end                 # multi-line

input :p, bind({1, x})                       # single-line, no label
input :p, bind({1, x}), label: "in"          # single-line, with label

input :p, label: "in" do                     # multi-line, with label
  if x > 0, do: bind({1, x}), else: bind({2, x})
end
```

## Reuse

`colset/1`, `var/1`, and `val/1` are re-exported from
`ColouredFlow.Notation.*` so existing notation users have one mental model.
Everything else (`name`, `version`, `place`, `initial_marking`,
`transition`, `input`, `output`, `guard`, `action`, `function`,
`termination`, `on_markings`) is new and lives under
`ColouredFlow.DSL.*`.

## Top-level macros

### `name/1`

Set the human-readable workflow name. Compile-time only.

    name "Traffic Light"

### `version/1`

Set the workflow version (any string the caller chooses; semver is
conventional).

    version "1.0.0"

### `colset/1`

Re-exported from `ColouredFlow.Notation.Colset`. Declares a colour set.

    colset int()    :: integer()
    colset bool()   :: boolean()
    colset status() :: ok | err
    colset point()  :: {integer(), integer()}

### `var/1`

Re-exported from `ColouredFlow.Notation.Var`. Declares a variable bound to
a colour set.

    var x :: int()

### `val/1`

Re-exported from `ColouredFlow.Notation.Val`. Declares a constant bound to
a colour set.

    val pi :: float() = 3.14

### `place/2`

Declare a place. The first argument is the place name (atom; converted to a
string for the underlying `%Place{}`); the second is the colour set name
(atom).

    place :input, :int
    place :output, :int

### `initial_marking/2`

Declare the initial marking for a place. Multiple `initial_marking/2`
calls may target different places; they are scattered freely between
other declarations.

    initial_marking :input, ~MS[1, 2, 3]

### `function/2` and `function/3`

Declare a user-defined function (CPN procedure) usable in arc, guard,
action, and termination expressions. The arguments listed in the head
must appear as free variables in the body. The return type after `::` is
the result colour set.

    function is_even(x) :: bool(), do: Integer.mod(x, 2) === 0

    function double(x) :: int() do
      x * 2
    end

### `transition/2`

Declare a transition. The block accepts `guard/1`, `action/1`, `input/2,3`
and `output/2,3`.

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
sub-macros. Currently only `on_markings/1` is supported. Future criterion
kinds (`on_time`, `on_workitem_count`, etc.) plug in here without
changing call sites.

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

Boolean expression over bound variables. Optional. Returning a falsy
value disables the transition for the current binding.

    guard x > 0
    guard do
      x > 0 and is_even(x)
    end

### `action/1`

Expression evaluated when the transition fires. Optional. Use for output
bindings (when an outgoing arc references an unbound variable) and for
side effects.

    action :ok
    action do
      log("fired")
      :ok
    end

### `input/2` and `input/3`

Declare an incoming arc (place → transition). The expression must use the
`bind/1` keyword to consume tokens. Options: `:label`.

    input :input, bind({1, x})
    input :input, bind({1, x}), label: "in"
    input :input, label: "in" do
      if x > 0, do: bind({1, x}), else: bind({2, x})
    end

### `output/2` and `output/3`

Declare an outgoing arc (transition → place). The expression evaluates to
the multiset of tokens produced. Options: `:label`.

    output :output, {1, x}
    output :output, {1, x}, label: "out"
    output :output, label: "out" do
      if x > 0, do: {1, x}, else: {0, x}
    end

## Termination-scope macros

### `on_markings/1`

Boolean expression over the special variable `markings` (a map of place
name → token multiset). Returning a truthy value terminates the enactment
with reason `:explicit`.

    on_markings do
      match?(
        %{"output" => out_ms} when multi_set_coefficient(out_ms, 1) >= 5,
        markings
      )
    end

## Compile-time validation

The `@before_compile` hook builds a `%ColouredPetriNet{}` from the
accumulated declarations and runs the existing
`ColouredFlow.Validators.run/1` pipeline:

- colour-set declarations are well-formed,
- place colour-set references resolve,
- arc endpoints exist,
- incoming arcs use `bind/1`,
- free variables in expressions resolve to declared `var/1` (or function
  arguments),
- structural sanity (no orphan places, no duplicate names, etc.).

Any failure raises a clear compile-time error pointing to the offending
line.

## File layout

Macros are partitioned by concern; the entry module re-exports them via
`__using__/1`.

- `ColouredFlow.DSL`                       — entry, `__using__/1`, top-level macros
- `ColouredFlow.DSL.Builder`               — `@before_compile` hook
- `ColouredFlow.DSL.Place`                 — `place/2`, `initial_marking/2`
- `ColouredFlow.DSL.Transition`            — `transition/2`, `guard/1`, `action/1`
- `ColouredFlow.DSL.Arc`                   — `input/{2,3}`, `output/{2,3}`
- `ColouredFlow.DSL.Function`              — `function/{2,3}`
- `ColouredFlow.DSL.Termination`           — `termination/1`, `on_markings/1`
- `ColouredFlow.DSL.ExpressionHelper`      — AST → `%Expression{}` conversion

## Out of scope

- Runner integration: spawning enactments, persisting flows. The DSL
  produces a definition; how it is run is the caller's choice.
- Visualisation / diagram generation. Could be layered on top of
  `cpnet/0`.
- Live editing / hot reload. Workflows are expected to be defined in
  source and recompiled.
