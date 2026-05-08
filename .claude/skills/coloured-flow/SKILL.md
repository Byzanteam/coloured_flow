---
name: coloured-flow
description: Build a Coloured Petri Net workflow as a `use ColouredFlow.DSL` Elixir module. Use when the user asks to model concurrent or stateful processes, state machines with event sourcing, business flows that decompose into independently firable steps with shared state, or anything described as a workflow, pipeline with branches, choreography, or saga. Output is a single Elixir module validated at `mix compile`. Skip for purely sequential scripts, one-shot calculations, or flows with no concurrency and no shared state.
---

# ColouredFlow workflow modelling

Solve the problem by emitting a `defmodule … do; use ColouredFlow.DSL; … end` module. The DSL's `@before_compile` pass runs the full validator suite, so a green `mix compile` is the proof that the model is structurally sound — undeclared colour sets, unbound variables, free vars not provable from incoming arcs, dangling arc endpoints, and mismatched colour sets all surface there. Dynamic side effects (actions, lifecycle reactions) live inside the same module and dispatch through the runner's `LifecycleHooks` callbacks.

## When to use

Reach for this skill when the problem has at least one of:

- multiple steps that can fire concurrently or in any order;
- shared state observed across steps (token counts, queues, locks, set membership);
- explicit state-machine transitions where the next step depends on what is currently true;
- a need for replay, snapshot, or event-sourced recovery;
- business rules expressed as preconditions on shared state rather than control flow inside one function.

Skip it when:

- the flow is a straight line of function calls — write a function;
- there is no state shared between steps — write a pipeline (`|>`);
- the problem is dominated by data transformation rather than control flow;
- one process / GenServer with a `:state` atom is enough.

## Mental model

| CPN concept | Elixir DSL                    | Read as                                                  |
| ----------- | ----------------------------- | -------------------------------------------------------- |
| place       | `place :name, :colset`        | typed slot that holds tokens                             |
| token       | element of `~MS[…]`           | single piece of data sitting on a place                  |
| colour set  | `colset name() :: type()`     | type that a place's tokens must conform to               |
| variable    | `var x :: colset()`           | binding consumed by an arc, reusable in expressions      |
| constant    | `val k :: colset() = literal` | named compile-time literal                               |
| transition  | `transition :name do … end`   | event that consumes input tokens and produces outputs    |
| input arc   | `input :place, bind({n, x})`  | consume `n` copies matching `x` from `:place`            |
| output arc  | `output :place, {n, expr}`    | put `n` copies of `expr` onto `:place`                   |
| guard       | `guard expr`                  | bool over bound vars; falsy disables the binding         |
| action      | `action do … end`             | side effect run after the firing commits                 |
| termination | `on_markings do … end`        | predicate over the current marking that ends the run     |
| function    | `function f(args) :: ret()`   | pure CPN procedure callable from any expression position |

A *binding* is a concrete assignment of variables to consumed tokens that satisfies every input arc and the guard. Each enabled binding becomes a *workitem* (`enabled → started → completed`). Firing it emits an `Occurrence` — the event-sourced ground truth that the runner replays to rebuild state after a crash.

Tokens are bag-multiplied: `bind({2, 1})` consumes *two* copies of the literal `1`; `output :p, {3, x}` puts *three* copies of `x`. The first element is the multiplicity, the second is the value.

## Minimal viable workflow

```elixir
defmodule MyApp.Workflows.PassThrough do
  use ColouredFlow.DSL

  name "Pass Through"
  version "1.0.0"

  colset int() :: integer()
  var x :: int()

  place :input, :int
  place :output, :int

  initial_marking :input, ~MS[1 2 3]

  transition :move do
    input :input, bind({1, x})
    output :output, {1, x}
  end
end
```

Compile it: `mix compile`. Any structural problem (undeclared colour set, unbound variable, type mismatch, missing arc endpoint) raises a `CompileError` pointing at the offending line. From `iex -S mix`, `MyApp.Workflows.PassThrough.cpnet()` returns the materialised `%ColouredPetriNet{}`.

## Modelling checklist

Before writing the module, answer in order:

1. **What types flow through this system?** → one `colset` per type. Reuse primitives (`int()`, `bool()`, `binary()`); add tuple/union colsets for compound data.
2. **What are the stable states the system passes through?** → one `place` per state. Place names are atoms; their stored form is the string version (use the string when matching `markings` in termination).
3. **What events move the system between states?** → one `transition` per event.
4. **For each transition: what must already be true?** → input arcs (consume from places) and `guard` (boolean over bound vars).
5. **What changes after the event fires?** → output arcs (produce to places) and optional `action do … end` for side effects.
6. **What does it mean for the workflow to be done?** → `termination do; on_markings do … end; end`. Otherwise the runner stops only when no transition is enabled (`:implicit`) or the operator forces it (`:force`).
7. **What initial state?** → `initial_marking :place, ~MS[…]` for every place that should not start empty.

## Output discipline

- One workflow = one module. Keep helper logic (renderers, drivers) as private/public functions on the same module so the lifecycle hook bodies can call them by name.
- Every `colset` that appears in a `place` declaration must be declared. The atom in `place :p, :int` refers to a `colset int() :: …` — the parens form is mandatory at the declaration site.
- Variables must be declared with `var` before any arc references them. The DSL does not infer.
- Inside `output do … end` blocks, every branch must evaluate to either a `{multiplicity, value}` tuple or `~MS[…]`-shaped data. `if`/`case` works as long as every branch returns the same colour set.
- Inside `input do … end` blocks, every branch must be a `bind/1` call.

## Validation loop

1. `mix compile` — must succeed; treat each `CompileError` as a model bug, fix at the source.
2. `iex -S mix` → `cpnet()` returns a struct → `__cpn__(:initial_markings)` returns the seed list.
3. For runtime testing, see `references/running.md`.
4. For larger / more interesting shapes, copy from `references/patterns.md` and adapt.

## References

- `references/dsl-reference.md` — every macro, every option, exhaustive surface area.
- `references/patterns.md` — canonical workflow patterns (sequence, parallel-split, deferred choice, AND-join, thread-merge, transmission protocol, state machine with lifecycle drive).
- `references/running.md` — set up storage, insert flow + enactment, drive workitems, observe markings, wire lifecycle hooks, terminate.
- Project-level authoritative sources: `lib/coloured_flow/dsl/spec.md` (DSL spec) and `examples/traffic_light.livemd` (full Livebook walkthrough). Read these when references are insufficient.
