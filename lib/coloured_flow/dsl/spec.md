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

`cpnet/0` is the **main API**: it returns the static CPN — colour sets,
variables, places, transitions, arcs, and termination criteria — that
the runner reuses across every enactment of the workflow.

`__cpn__/1` is a **reflection helper** for declaration metadata
(modeled after `Ecto.Schema.__schema__/1`). Pass an atom key to read
the corresponding piece of workflow metadata. `:initial_markings`
returns the list of `%Marking{}` declared via `initial_marking/2`;
this is enactment-seed data, deliberately *not* folded into `cpnet/0`.
Pass it to `Storage.insert_enactment/1` (or your own runner glue) when
starting an enactment.

Higher-level integration — spawning enactments, persisting flows,
visualisation — is left to the existing `ColouredFlow.Runner.*` API.

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
`initial_markings/0` on the host module. The cpnet definition itself is
not affected.

    initial_marking :input, ~MS[1 2 3]

### `function/2` and `function/3`

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

Any failure raises a `CompileError` pointing to the offending macro
call.
