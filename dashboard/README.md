# ColouredFlow Dashboard

A standalone Phoenix + React SPA that serves three roles for a
[`ColouredFlow`](../) runtime: operator console, debug surface, and live
presentation tool. Built on the main repo's already-exposed runner APIs and
telemetry events; the main `lib/coloured_flow/**` tree stays untouched.

## Architecture

```
                    ┌──────────────────────────────────────────────┐
                    │  ColouredFlow runner (lib/coloured_flow/**)  │
                    │  ── unchanged by this app ──                 │
                    │                                              │
                    │  emits :telemetry events on every enactment  │
                    │  + workitem lifecycle transition             │
                    └─────────────────────┬────────────────────────┘
                                          │
                                          ▼
        ┌───────────────────────────────────────────────────────────┐
        │  Dashboard.TelemetryBridge                                │
        │   • attaches all `[:coloured_flow, :runner, :enactment,*]`│
        │     events via `:telemetry.attach_many/4`                 │
        │   • spawns a Task per event so the runner never blocks    │
        │   • broadcasts onto three PubSub topic shapes:            │
        │       cf:inbox  |  cf:enactment:{id}  |  cf:flow:{topic}  │
        └─────────────────────┬─────────────────────────────────────┘
                              │ Phoenix.PubSub
                              ▼
        ┌───────────────────────────────────────────────────────────┐
        │  Musubi root stores (per-route)                           │
        │                                                           │
        │    /                  → InboxStore                        │
        │    /enactments/:id    → EnactmentDetailStore              │
        │    /flows[, /:module] → FlowCatalogStore                  │
        │                                                           │
        │  Each store subscribes to its topic; payloads translate   │
        │  into Musubi stream_insert / stream_delete / assign ops   │
        │  so JSON Patch envelopes pushed to the SPA stay small.    │
        └─────────────────────┬─────────────────────────────────────┘
                              │ Musubi WS channel
                              ▼
        ┌───────────────────────────────────────────────────────────┐
        │  React 19 SPA (ui/)                                       │
        │   • Vite + React Router 7 + Kumo UI 2.3                   │
        │   • React Flow net diagram with token-count badges        │
        │   • Outputs drawer + structured inference                 │
        │   • Replay scrubber + step-through autoplay               │
        │   • Embed mode (?embed=1) + dark theme                    │
        └───────────────────────────────────────────────────────────┘
```

## Running locally

### Prerequisites

* Elixir `~> 1.18` (musubi 0.6 transitive pin)
* Node `>= 20` + `pnpm`
* PostgreSQL on `postgres:postgres@localhost`

### Backend

```sh
cd dashboard
mix deps.get
mix ecto.setup      # create DB + migrate + run priv/repo/seeds.exs
mix phx.server      # boots Phoenix on :4000 (or PORT env)
```

`mix phx.server` no longer auto-seeds. Booting against a fresh database
brings the app up with zero flows and zero enactments; populate them via
`mix ecto.setup` (one-shot) or `mix run priv/repo/seeds.exs` (re-runs
against an existing DB). Both are idempotent — a second invocation
reuses the existing rows rather than inserting duplicates.

`mix ecto.reset` drops and recreates the dev DB end-to-end. To wipe the
seed rows without losing the schema, use `mix cf.dashboard.reset_seed_db`
(MIX_ENV=dev only) and then re-run the seeds script.

The application uses the same Postgres database as the parent
`coloured_flow` test suite. `Repo` is `ColouredFlowDashboard.Repo`;
`coloured_flow`'s storage delegator is configured to route through it.

### SPA

```sh
cd dashboard/ui
pnpm install
pnpm dev           # Vite on :4103, proxies /socket to Phoenix :4000
```

### Demo flows seeded by `priv/repo/seeds.exs`

| Flow                         | Role                                              |
| ---------------------------- | ------------------------------------------------- |
| `ApprovalFlow`               | M2 outputs drawer — binary free vars              |
| `IncidentTriageFlow`         | M5 structured form — enum + boolean + string      |
| `TrafficLightFlow`           | M4 diagram — choreographed multi-place flow       |
| `PiAgentFlow`                | List-typed markings + atom-union colour sets      |

## Routes

| Path                       | Description                                         |
| -------------------------- | --------------------------------------------------- |
| `/`                        | Inbox of live workitems across every enactment     |
| `/enactments/:id`          | Net diagram + tabs (Markings/Workitems/Occurrences/Telemetry/Debug) |
| `/flows`                   | Flow catalog                                       |
| `/flows/:module`           | Flow detail                                        |
| `?embed=1`                 | Strips sidebar + headers for live screen-share     |

## Commands

```sh
mix precommit                    # deps check + format check + WAE compile + credo --strict + dialyzer + test
mix test                         # full backend suite
cd ui && pnpm typecheck          # tsc --noEmit
cd ui && pnpm test               # vitest
cd ui && pnpm build              # production bundle into ../priv/static
cd ui && pnpm smoke              # WS + bundle invariants against $SMOKE_BASE_URL
```

## Theming

OKLCH tokens declared in `ui/src/styles/app.css` under `@theme`. Three
activation paths:

* Default — light mode.
* `[data-theme="dark"]` — explicit user pick (`ThemeToggle` writes to
  `localStorage["cf-theme"]`).
* `@media (prefers-color-scheme: dark)` — visitors who never touched the
  toggle.

Kumo's `data-mode="dark"` attribute mirrors the resolved theme so the
library's primitives flip with the dashboard's tokens.
