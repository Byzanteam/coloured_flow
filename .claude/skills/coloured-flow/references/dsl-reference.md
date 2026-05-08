# DSL reference

Every macro the DSL exposes, every option it accepts, with a runnable snippet. Authoritative source: `lib/coloured_flow/dsl/spec.md`. This page is a working reference; reach for the spec when something here is silent.

## Module setup

```elixir
defmodule MyApp.Workflows.MyFlow do
  use ColouredFlow.DSL
  # … declarations …
end
```

### Module options

`use ColouredFlow.DSL` accepts:

- `:task_supervisor` — registered name of a `Task.Supervisor` that wraps every `action do … end` body and every `on_enactment_*` body. Without it, bodies fall back to an unsupervised `Task.start/1`. Production code should always provide one.

```elixir
use ColouredFlow.DSL, task_supervisor: MyApp.WorkflowTaskSup
```

## Universal expression rule

Every macro that takes an expression follows the same shape:

- **Single-line**: the expression is the last positional argument.
- **Multi-line**: pass a `do … end` block; the block body *is* the expression. There is no `expr do … end` wrapper.
- **Options** (e.g., `label:`): keyword arguments only, between the positional arguments and the `do` block.

```elixir
guard x > 0                               # single-line
guard do x > 0 and y > 0 end              # multi-line

input :p, bind({1, x})                    # single-line, no label
input :p, bind({1, x}), label: "in"       # single-line, label
input :p, label: "in" do                  # multi-line, label
  if x > 0, do: bind({1, x}), else: bind({2, x})
end
```

## Top-level macros

### `name/1`

Human-readable name. Optional but recommended.

```elixir
name "Order Pipeline"
```

### `version/1`

Version string. Free-form; semver is conventional. Optional.

```elixir
version "1.0.0"
```

### `colset/1`

Declares a colour set. Re-exported from `ColouredFlow.Notation.Colset`.

```elixir
colset int()    :: integer()
colset bool()   :: boolean()
colset bin()    :: binary()
colset signal() :: {}                            # unit type
colset point()  :: {integer(), integer()}        # tuple
colset status() :: ok | err                      # union of atoms
colset id_data() :: {integer(), binary()}        # heterogeneous tuple
```

The colour-set name is referenced as an atom in `place/2`: `place :input, :int` refers to `colset int() :: …`.

### `var/1`

Declares a variable bound to a colour set. Re-exported from `ColouredFlow.Notation.Var`. Variables are reusable across transitions but are scoped by where they appear (each transition's incoming arcs bind their own copy).

```elixir
var x :: int()
var s :: signal()
var n :: no()
```

### `val/1`

Declares a constant. Re-exported from `ColouredFlow.Notation.Val`.

```elixir
val pi :: float() = 3.14
val limit :: int() = 100
```

### `place/2`

Declares a place. Place names are atoms; the underlying `%Place{}` stores them as strings, which matters when matching against the `markings` map in termination.

```elixir
place :input, :int
place :output, :int
```

### `initial_marking/2`

Declares an initial marking on a place. Multiple `initial_marking/2` calls accumulate in declaration order. The `cpnet/0` struct itself is *not* affected; the markings are exposed via `__cpn__(:initial_markings)` and consumed when an enactment is started.

```elixir
initial_marking :input, ~MS[1 2 3]
initial_marking :output, ~MS[]
initial_marking :red_ew, ~MS[{}]                 # signal token
```

The `~MS` sigil literal: `~MS[a b c]` = three tokens (`a`, `b`, `c`), `~MS[{2, x}]` = two copies of `x`, `~MS[{}]` = single unit token.

### `function/1` and `function/2`

Declares a user-defined function (CPN procedure) callable from any arc / guard / action / termination expression.

```elixir
function is_even(x) :: bool(), do: Integer.mod(x, 2) === 0

function double(x) :: int() do
  x * 2
end
```

Argument names listed in the head must appear as free variables in the body; the colour set after `::` is the result type. Function names must be unique within a module.

### `transition/2`

Declares a transition. The block accepts `guard/1`, `action/1`, `input/{2,3}`, and `output/{2,3}`.

```elixir
transition :pass_through do
  guard x > 0

  input :input, bind({1, x})
  output :output, {1, x * 2}

  action do
    :ok
  end
end
```

### `termination/1`

Declares termination criteria. The block currently accepts `on_markings/1`. Future kinds (`on_time`, `on_workitem_count`, …) plug in here without changing call sites.

```elixir
termination do
  on_markings do
    match?(
      %{"output" => out_ms} when multi_set_coefficient(out_ms, 1) >= 5,
      markings
    )
  end
end
```

## Transition-scope macros

### `guard/1`

Boolean expression over bound variables. Optional. A falsy result disables the transition for the current binding. At most one `guard` per transition.

```elixir
guard x > 0
guard do
  x > 0 and is_even(x)
end
```

### `action/1`

Side-effect body, evaluated by the auto-generated `on_workitem_completed/2` callback after the firing commits. Optional. At most one `action` per transition. The body compiles into `__action_for__/3` and runs inside the configured `Task.Supervisor` (or unsupervised `Task.start/1` when none).

Magic bindings inside the body:

- every CPN variable bound by this transition's incoming arcs;
- `event` — `%{enactment_id, markings, workitem, occurrence, binding}` of the completed-workitem event;
- `options` — the keyword list registered with the hook module via the `{module, options}` tuple form (or `[]` when the module is registered alone).

```elixir
action do
  Phoenix.PubSub.broadcast(
    MyApp.PubSub,
    options[:topic] || "fires",
    {:fired, event.workitem.binding_element.transition, x}
  )
end
```

Exceptions raised from `action` bodies are caught and discarded — the runner must never block on user side effects. Anything that has to fail loudly should fail at definition time, not runtime.

### `input/2` and `input/3`

Declares an incoming arc (place → transition). The expression must use `bind/1` to consume tokens. Option: `:label`.

```elixir
input :input, bind({1, x})
input :input, bind({1, x}), label: "in"
input :input, label: "in" do
  if x > 0, do: bind({1, x}), else: bind({2, x})
end
input :merge, bind({2, 1})                       # require two copies of literal 1
```

### `output/2` and `output/3`

Declares an outgoing arc (transition → place). The expression evaluates to a `{multiplicity, value}` tuple, a multiset, or — inside a `do` block — any expression whose every branch evaluates to the same colour set. Option: `:label`.

```elixir
output :output, {1, x}
output :output, {1, x}, label: "out"
output :output, label: "out" do
  if x > 0, do: {1, x}, else: {0, x}             # zero copies = no token produced
end
output :a, {1, {n, d}}                           # heterogeneous tuple token
```

## Termination-scope macros

### `on_markings/1`

Boolean expression over the magic variable `markings` — a map keyed by *string* place names (because `place :input` is stored as `"input"`) to token multisets. Truthy result terminates the enactment with reason `:explicit`. At most one `on_markings` per workflow.

```elixir
on_markings do
  match?(
    %{"output" => out_ms} when multi_set_coefficient(out_ms, 1) >= 5,
    markings
  )
end
```

`multi_set_coefficient/2` returns the multiplicity of a value in a multiset.

## Lifecycle macros

These compile to `ColouredFlow.Runner.Enactment.LifecycleHooks` callbacks. They are the structured per-instance counterpart to `:telemetry`. Each may appear at most once per workflow; a duplicate is a compile-time error. Magic bindings: `event` (event payload) and `options` (the keyword list registered alongside the hook module via `{module, options}`).

### `on_enactment_start/1`

Runs after the enactment process has booted and replayed history.

```elixir
on_enactment_start do
  TrafficLight.render(options[:frames], event.markings)
  TrafficLight.drive_next(event.enactment_id, "turn_green_ew")
end
```

### `on_enactment_terminate/1`

Runs when termination is reached (any kind).

```elixir
on_enactment_terminate do
  Logger.info("Enactment #{event.enactment_id} terminated: #{inspect(event.reason)}")
end
```

### `on_enactment_exception/1`

Runs when the enactment enters the `:exception` state.

```elixir
on_enactment_exception do
  Logger.error("Exception in #{event.enactment_id}: #{inspect(event.reason)}")
end
```

## Generated module surface

A module that uses `ColouredFlow.DSL` exposes:

```elixir
MyFlow.cpnet()                                    # %ColouredPetriNet{}
MyFlow.__cpn__(:name)                             # String.t() | nil
MyFlow.__cpn__(:version)                          # String.t() | nil
MyFlow.__cpn__(:initial_markings)                 # [%ColouredFlow.Enactment.Marking{}]

MyFlow.insert_enactment(flow_id)                  # {:ok, %Schemas.Enactment{}}
MyFlow.insert_enactment(flow_id, [%Marking{}])
MyFlow.insert_enactment(flow_id, [%Marking{}], opts)
MyFlow.start_enactment(enactment_id, opts)        # DynamicSupervisor.on_start_child()

# LifecycleHooks callbacks (auto-dispatched)
MyFlow.on_workitem_completed(event, options)      # always emitted; dispatches `action` bodies
MyFlow.on_enactment_start(event, options)         # only if `on_enactment_start` declared
MyFlow.on_enactment_terminate(event, options)     # only if declared
MyFlow.on_enactment_exception(event, options)     # only if declared
```

`cpnet/0` is the **main API** — the static CPN reused across every enactment of the workflow. `__cpn__/1` is a **reflection helper** modeled after `Ecto.Schema.__schema__/1`; pass an atom key to read declaration metadata.

`insert_enactment/3` is a thin wrapper over `ColouredFlow.Runner.Storage.insert_enactment/1`. It is *not* idempotent — every call inserts a fresh row, so application code must deduplicate at boot if needed. The flow row itself must already exist; insert flows directly via the storage primitives:

- `Default` backend: `%Schemas.Flow{} |> Ecto.Changeset.cast(...) |> Repo.insert!()`
- `InMemory` backend: `Storage.InMemory.insert_flow!/1`

`start_enactment/2` registers the workflow module as the per-instance `LifecycleHooks`. To inject per-instance configuration, pass `lifecycle_hooks: {__MODULE__, options}` — the `options` keyword list is forwarded to every callback as the second argument and exposed inside DSL bodies as the magic binding `options`. To disable hooks for one enactment, pass `lifecycle_hooks: nil`.

## Compile-time validation

The `@before_compile` hook builds a `%ColouredPetriNet{}` from the accumulated declarations, runs `ColouredFlow.Builder.build/1` (which populates `action.outputs` from arc/guard analysis), and runs `ColouredFlow.Validators.run/1`. Failures raise `CompileError` with `{file, line}` metadata captured at macro expansion. The validator checks:

- colour-set declarations are well-formed;
- place / variable / constant colour-set references resolve;
- arc endpoints exist (place, transition);
- incoming arcs use `bind/1`;
- free variables in expressions resolve to a `var/1` (or function arg);
- guard variables are bound by the same transition's incoming arcs;
- function names are unique and result descrs fully resolve;
- termination criteria reference only `markings`.
