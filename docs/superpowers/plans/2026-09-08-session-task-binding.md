# Session Task Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use TDD and execute this plan task-by-task.

**Goal:** Bind one host conversation to a real governed TaskRoot, Contract, Ledger, running Attempt, and role before a bounded Canary path is written.

**Architecture:** An external registration script validates canonical task artifacts and writes a private session binding keyed by host conversation hash. PreToolUse applies the binding requirement only inside one configurable Canary policy root. Missing, stale, out-of-scope, or non-writer bindings return `force_ask`; all unrelated paths remain observe-only.

---

### Task 1: RED Binding Contract

- [x] Add tests for missing binding, valid active binding, stopped Attempt, out-of-scope target, privacy, and unrelated-path compatibility.
- [x] Confirm the test fails because the registration script and Hook behavior are absent.

### Task 2: Binding Registry And Hook Gate

- [x] Add `new-desktop-session-binding.ps1` with canonical Contract/Ledger/Attempt validation.
- [x] Add bounded PreToolUse binding resolution and `force_ask` behavior.
- [x] Persist only binding hashes in Hook event/correlation records.
- [x] Keep the private binding record explicit about its unattested operator-script authority.

### Task 3: Release And Canary Setup

- [x] Update capability/component/package/docs surfaces.
- [x] Run focused and full verification.
- [x] Install runtime and desktop plugin transactionally.
- [x] Create one empty governed TEMP Canary task with a running Attempt.
- [x] Do not commit or push.
