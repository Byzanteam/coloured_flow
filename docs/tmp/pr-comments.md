# PR #89 — Unresolved Comments

Latest commit: `5475998`. 7 unresolved (5 stale copilot + 2 new fahchen).

## Open

### 1. `test/coloured_flow/dsl/listener_e2e_test.exs` (file-level) — @copilot
> setup_flow!/0 not idempotent vs PR description.

Thread: `PRRT_kwDOMZc9dM5_KOFJ` / Comment: `3177549638`
**Status:** keep  **Decision:** stale — file renamed to `lifecycle_hooks_e2e_test.exs` and `setup_flow!` removed entirely in `5475998` (Q1).

---

### 2. `lib/coloured_flow/dsl/spec.md` (file-level) — @copilot
> ActionHandler vs Listener naming mismatch.

Thread: `PRRT_kwDOMZc9dM5_KOFW` / Comment: `3177549653`
**Status:** keep  **Decision:** stale — module renamed `ActionHandler → Listener → LifecycleHooks` (final). 7 callbacks (`on_workitem_reoffered` dropped). spec.md aligned in `5475998`. PR title/description need manual update.

---

### 3. `lib/coloured_flow/dsl/builder.ex` (file-level) — @copilot
> setup_flow!/0 doc says raise on missing name but impl doesn't validate.

Thread: `PRRT_kwDOMZc9dM5_KOFh` / Comment: `3177549664`
**Status:** keep  **Decision:** stale — `setup_flow!/0` removed entirely in `5475998`. DSL no longer inserts flows.

---

### 4. `lib/coloured_flow/runner/enactment/enactment.ex` #310 — @copilot
> apply_calibration dispatches workitem callbacks before on_enactment_start during boot.

Thread: `PRRT_kwDOMZc9dM5_KOFo` / Comment: `3177549671`
**Status:** keep  **Decision:** principle is "each callback fires after its own telemetry event"; current code obeys that. Cross-callback ordering (workitem_enabled before enactment_start) is acceptable because each callback follows its own emit point.

---

### 5. `lib/coloured_flow/dsl/storage.ex` (file-level) — @copilot
> Idempotency claim mismatch.

Thread: `PRRT_kwDOMZc9dM5_KOFq` / Comment: `3177549673`
**Status:** keep  **Decision:** stale — file `lib/coloured_flow/dsl/storage.ex` deleted entirely in `5475998` (Q1).

---

### 6. `lib/coloured_flow/runner/enactment/enactment.ex` (file-level) — @fahchen
> 这个文件太大了，可以把新增的部分抽象出来

Thread: `PRRT_kwDOMZc9dM5_Kedo` / Comment: `3177634901`
**Status:** fix  **Decision:** extract `dispatch_lifecycle/3` + `dispatch_post_calibration/3` into new module `ColouredFlow.Runner.Enactment.LifecycleHooks.Dispatcher`. API takes `%Enactment{}` state struct directly (internal helper, coupling acceptable). `:abnormal_exit` line stays in `terminate/2`.

---

### 7. `test/coloured_flow/dsl/lifecycle_hooks_e2e_test.exs` #37 — @fahchen
> 通过 options 传进来，而不是 persistent term

Thread: `PRRT_kwDOMZc9dM5_KfCI` / Comment: `3177637783`
**Status:** fix  **Decision:** drop `:persistent_term` test-pid hack. Pass `test_pid` via `lifecycle_hooks: {Workflow, [test_pid: self()]}` options. DSL bodies read `options[:test_pid]` and send. Apply same pattern to `lifecycle_hooks_dispatch_test.exs` (also uses persistent_term).

---
