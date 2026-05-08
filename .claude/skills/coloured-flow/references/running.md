# Running an enactment

Once the workflow module compiles, the runner turns it into a supervised, persistent process tree. This page is the recipe for getting from "module compiles" to "instance is live and observable". Reduced from `examples/traffic_light.livemd`; the same shape works for any workflow.

## Storage backend

Pick the backend before starting anything. Configured globally:

```elixir
# config/config.exs
config :coloured_flow, ColouredFlow.Runner.Storage,
  storage: ColouredFlow.Runner.Storage.InMemory   # tests / dev
  # storage: ColouredFlow.Runner.Storage.Default  # prod (Ecto/Postgres)
```

| Backend           | Use            | Storage                                                              |
| ----------------- | -------------- | -------------------------------------------------------------------- |
| `Storage.InMemory`| tests, demos   | ETS-backed, in-process                                               |
| `Storage.Default` | production     | Ecto/Postgres; migrations under `lib/coloured_flow/runner/storage/migrations/V0..V3` |

For Livebook / `iex` use:

```elixir
{:ok, _pid} = ColouredFlow.Runner.Storage.InMemory.start_link()
{:ok, _pid} = ColouredFlow.Runner.Supervisor.start_link()
```

## Insert flow row + enactment row

A *flow* is the persisted CPN definition; an *enactment* is one running instance of that flow. Both must exist in storage before the runner can start the GenServer.

### InMemory

```elixir
import ColouredFlow.Runner.Storage.InMemory, only: :macros

alias ColouredFlow.Runner.Storage.InMemory

flow = InMemory.insert_flow!(MyFlow.cpnet())
{:ok, enactment_record} = MyFlow.insert_enactment(flow(flow, :id))
enactment_id = enactment(enactment_record, :id)
```

The `flow/2` and `enactment/2` macros are field accessors for the InMemory record types.

### Default (Ecto/Postgres)

```elixir
alias ColouredFlow.Runner.Storage.Schemas

{:ok, %Schemas.Flow{id: flow_id}} =
  %Schemas.Flow{}
  |> Ecto.Changeset.cast(%{cpn: MyFlow.cpnet()}, [:cpn])
  |> MyApp.Repo.insert()

{:ok, %Schemas.Enactment{id: enactment_id}} = MyFlow.insert_enactment(flow_id)
```

`MyFlow.insert_enactment/1` uses the markings declared via `initial_marking/2`. To override per-instance, pass them explicitly:

```elixir
MyFlow.insert_enactment(flow_id, [
  %ColouredFlow.Enactment.Marking{place: "input", tokens: ~MS[42 99]}
])
```

`insert_enactment/3` is *not* idempotent — every call inserts a fresh row. Deduplicate at the call site if you need that.

## Start the enactment

```elixir
{:ok, enactment_pid} = MyFlow.start_enactment(enactment_id)
```

The runner:

1. Loads the latest `Snapshot` (or the initial markings if no snapshot exists).
2. Replays `Occurrence`s after the snapshot via `CatchingUp`.
3. Recomputes enabled bindings via `WorkitemCalibration`.
4. Takes a fresh snapshot.
5. Goes idle, waiting for workitems to be driven externally or by lifecycle hooks.

### With per-instance options

When the workflow has lifecycle hooks (`action`, `on_enactment_*`) that need configuration, pass options as the second tuple element:

```elixir
{:ok, enactment_pid} =
  MyFlow.start_enactment(enactment_id,
    lifecycle_hooks: {MyFlow, [topic: "orders:42", frames: %{…}]}
  )
```

Inside any DSL body, `options` is the magic binding holding that keyword list:

```elixir
action do
  Phoenix.PubSub.broadcast(MyApp.PubSub, options[:topic], {:fired, x})
end
```

To disable hooks for one enactment, pass `lifecycle_hooks: nil`.

## Drive workitems

A *workitem* moves through `enabled → started → completed`. The runner enumerates `enabled` items but never auto-fires them — it waits for an external driver (a UI, an LLM, another supervisor process) to start and complete them.

```elixir
alias ColouredFlow.Runner.Enactment.WorkitemTransition
alias ColouredFlow.Runner.Storage

# Pick an enabled workitem for a given transition.
%{id: workitem_id} =
  enactment_id
  |> Storage.list_live_workitems()
  |> Enum.find(fn wi ->
    wi.state == :enabled and wi.binding_element.transition == "my_transition"
  end)

# Move it through the lifecycle.
{:ok, _started}   = WorkitemTransition.start_workitem(enactment_id, workitem_id)
{:ok, _completed} = WorkitemTransition.complete_workitem(enactment_id, {workitem_id, []})
```

The second element of the `complete_workitem/2` tuple is the *free-binding list* — values for any output free variables (`success` in the transmission protocol pattern). Pass `[]` when there are no free variables to resolve. Pass `[success: true]` (etc.) when the transition's outputs need them.

Workitems can also be **withdrawn** (`WorkitemTransition.withdraw_workitem/2`) when an external system decides the work has been cancelled, or **reoffered** (`WorkitemTransition.reoffer_workitem/2`) to recover from an exception state.

### Self-driving via `action`

For state machines that should run themselves, drive the next transition from inside an `action do … end` body. See `references/patterns.md` "State machine with lifecycle drive". The general shape:

```elixir
action do
  # … side effects …
  MyFlow.drive_next(event.enactment_id, "next_transition_name")
end
```

…where `drive_next/2` does the `list_live_workitems` + `start_workitem` + `complete_workitem` dance. Keep the helper on the workflow module so the action body can call it by a fully qualified name.

## Observe markings

```elixir
# Live workitems (one row per enabled / started / completed instance).
Storage.list_live_workitems(enactment_id)

# The enactment process state — markings + workitems + version.
:sys.get_state({:via, Registry, {ColouredFlow.Runner.Enactment.Registry, enactment_id}})
```

For streaming observation:

```elixir
# Cursor-based stream of workitem state changes.
ColouredFlow.Runner.Worklist.WorkitemStream.list_live(enactment_id)

# Live query — see `examples/traffic_light.livemd` for a full PubSub-backed observer.
ColouredFlow.Runner.Worklist.WorkitemStream.live_query(enactment_id, …)
```

## Termination

The runner ends an enactment in one of three modes:

| Reason     | Trigger                                                                                |
| ---------- | -------------------------------------------------------------------------------------- |
| `:implicit`| no firable workitems remain reachable                                                  |
| `:explicit`| the workflow's `on_markings` predicate evaluates truthy                                |
| `:force`   | `ColouredFlow.Runner.Termination.force_terminate(enactment_id, reason)` is called      |

If the enactment hits an error it cannot recover from, it transitions to the `:exception` state. From there it can be `:reoffer`-ed (returning to `:running`) or force-terminated.

## Lifecycle hooks beyond the DSL

The DSL macros (`on_enactment_start`, `on_enactment_terminate`, `on_enactment_exception`) compile to module callbacks. To register a *separate* hook module that does not use the DSL, implement the `ColouredFlow.Runner.Enactment.LifecycleHooks` behaviour and pass it explicitly:

```elixir
{:ok, enactment_pid} =
  MyFlow.start_enactment(enactment_id, lifecycle_hooks: {MyExternalHooks, [opts]})
```

That replaces the DSL-generated hook callbacks for this one enactment. The `action do … end` bodies inside the workflow still need `MyFlow` to be the hook module, so prefer the DSL form for normal use; the explicit form is for dashboards, audit logs, or testing harnesses that observe but do not change behaviour.

## Telemetry

The runner emits `:telemetry` events throughout the enactment lifecycle (booted, workitem-state-changed, occurrence-emitted, snapshotted, terminated, exception). See `lib/coloured_flow/runner/telemetry/` for the event names and payload shapes. Use telemetry for cross-cutting concerns (metrics, tracing); use lifecycle hooks for workflow-specific side effects.
