# AGENTS.md — `dashboard/`

This file intentionally carries only deltas specific to the dashboard
sub-application. Repo-wide rules (tooling defaults, scope discipline, the
"never mutate runtime config across tests" rule, etc.) live in the root
[`/AGENTS.md`](../AGENTS.md) / [`/CLAUDE.md`](../CLAUDE.md) and apply here
verbatim. Always read the root file first.

The previous contents of this file were generic Phoenix-generator boilerplate
that contradicted real project conventions (e.g. assumed LiveView templates,
Heroicons, `core_components.ex` — none of which this app uses). It was
removed deliberately; do not regenerate it from `mix phx.gen`.

## Dashboard-specific deltas

_None yet._ Add a bullet here only when a rule applies inside `dashboard/`
that does NOT hold in the parent repo. As of Phase 1 there are no such
deltas — the parent rules cover everything we need.

## Pointers

- Architecture, milestones, and acceptance criteria for this app live in
  `~/.paseo/plans/cf-dashboard.md`.
- The parent `coloured_flow` library MUST stay untouched throughout this
  epic; verify with `git diff main..HEAD -- lib/coloured_flow` before any
  commit lands.
- Musubi-specific contracts (socket shape, store callbacks, async API,
  stream wire ops) live in the musubi project's own AGENTS.md at
  `~/PersonalProjects/arbor/AGENTS.md`. Consult it when wiring root
  stores in Phase 7+.
