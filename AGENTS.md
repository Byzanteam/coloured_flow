# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Cursor, Aider, etc.) working in this repository. Follows the [agents.md](https://agents.md) convention.

## Overview

ColouredFlow is a 100% Elixir workflow engine built on [Coloured Petri Nets (CPN)](https://github.com/lmkr/cpnbook). It ships:

- A CPN ML expression language and evaluator.
- A DSL for defining nets in Elixir.
- An event-sourced runtime executing enactments (workflow instances) as GenServers.
- Pluggable storage — in-memory for tests, Ecto/Postgres for production.

## Commands

- `mix precommit` — **run before every commit.** Mirrors CI: deps check, format check, compile warnings-as-errors, credo, dialyzer, test.
- `mix test` — full suite. Needs Postgres at `postgres:postgres@localhost`; `test_helper.exs` auto-creates DB `coloured_flow_test`. Set `RESET_DB=1` to drop & recreate.
- `mix test path/to/file_test.exs:LINE` — single test.
- `mix format` · `mix credo --strict` · `mix dialyzer` — individual checks. Dialyzer PLTs cached at `priv/plts/`.

CI: `.github/workflows/elixir.yml` runs the same checks in parallel against Postgres 15.

## Architecture

The code splits into **static CPN structure**, **CPN semantics**, and the **enactment runner**.

### Module map (`lib/coloured_flow/`)

| Path | Role |
| --- | --- |
| `definition/` | Pure data model. `ColouredPetriNet` holds `colour_sets`, `places`, `transitions`, `arcs`, `variables`, `constants`, `functions`, optional `termination_criteria`. |
| `enactment/` | Runtime values: `Marking` (tokens on a place), `BindingElement` (transition bound to input tokens), `Occurrence` (fired binding — the event-source event). |
| `multi_set.ex` | Multiset token bag. Sigil: `~MS[{1, "a"}, {2, "b"}]`. |
| `notation/` | Elixir DSL: `colset/1`, `val/1`, `var/1`, `arc` macro. |
| `builder/` | Converts DSL input into a validated `ColouredPetriNet`. |
| `validators/` | Static definition checks (colour sets, arc typechecks) + enactment-time invariants. |
| `expression/` | CPN ML compiler/evaluator; builds guards and bindings for arc inscriptions. |
| `enabled_binding_elements/` | Given marking + transition, enumerates every firing binding. Core Petri-net semantics. |
| `runner/` | GenServer-based execution engine — see below. |

### Runner (`lib/coloured_flow/runner/`)

Turns a stored CPN + initial markings into a supervised, persistent process tree.

- **Supervision tree.** `Runner.Supervisor` → `Enactment.Registry` (via-tuple naming) + `Enactment.Supervisor` (`DynamicSupervisor`) → one `Runner.Enactment` GenServer per workflow instance.
- **Enactment state.** `markings`, live `workitems`, monotonically-increasing `version`. Keyed by `enactment_id`, `restart: :transient`. Boot: load latest `Snapshot` (or initial markings) → replay `Occurrence`s via `CatchingUp` → recompute enabled bindings via `WorkitemCalibration` → take new snapshot.
- **Workitem lifecycle.** `enabled → started → completed`, plus `reoffer` (exception recovery) and `withdraw` (system). State machine in `Runner.Enactment.Workitem`. Public API: `WorkitemTransition.{start,complete}_workitem`. Recomputation: `WorkitemCalibration`, `WorkitemCompletion`, `WorkitemConsumption`.
- **Enactment lifecycle.** `running → {terminated | exception}`; `exception` can recover to `running`. Logic in `Runner.Enactment.EnactmentTermination`, driven by `Runner.Termination`. Termination kinds:

  | Kind | Trigger |
  | --- | --- |
  | `:implicit` | no more firable workitems reachable |
  | `:explicit` | definition's `termination_criteria` met |
  | `:force` | user call |

- **Event sourcing.** Firing a binding element produces an `Occurrence`; snapshots are periodic roll-ups. Recovery = load snapshot + replay occurrences after it.
- **Storage** (`runner/storage/`). `Runner.Storage` behaviour; implementation picked via `Application.get_env(:coloured_flow, ColouredFlow.Runner.Storage)[:storage]`.

  | Implementation | Use | Location |
  | --- | --- | --- |
  | `Storage.Default` | production — Ecto/Postgres | `storage/schemas/`; migrations `storage/migrations/{V0,V1}` |
  | `Storage.InMemory` | tests | `storage/in_memory.ex` |

- **Worklist** (`runner/worklist/`). `WorkitemStream.live_query` + `list_live` stream live workitems via cursor (see `TrafficLight` example's `WorkitemPubSub`).
- **Telemetry** (`runner/telemetry/`). Events emitted throughout the enactment lifecycle.

## Conventions

- Prefer `typed_structor` over plain `defstruct` + `@type t` for new data types — used pervasively.
- DSL macros `colset`, `val`, `var`, `return` are registered as `locals_without_parens` — don't add parens when the formatter complains.
