# Antigravity Harness v2.0 — Reliable Maker Control Plane

## Objective

Raise Antigravity's reliability floor without suppressing its execution strength.
The harness must make scope expansion explicit, persist resumable state, make
side effects idempotent, bind verification to the current workspace, separate
maker and checker authority, and prevent unsupported completion claims.

## Non-Goals

- Do not create a second agent runtime.
- Do not claim that prompts can eliminate model or service failures.
- Do not install into the real `$env:USERPROFILE\.gemini` during source work.
- Do not record raw prompts, hidden reasoning, secrets, or complete tool output.
- Do not let an agent approve deployment, migration, publication, or destructive
  effects without the user.

## Invariants

1. Declared, implemented, available, passed, verified, and approved are distinct.
2. A maker may provide evidence but cannot issue `verified`; self-reported
   reviewer identity is not trusted authority.
3. Verification is invalid when the checked workspace fingerprint changes.
4. A success-shaped payload never overrides a nonzero child-process exit.
5. Scope, file, dependency, and side-effect budgets fail closed.
6. Retries of one logical side effect reuse an idempotency key and inspect state.
7. `.gemini-private` is a marker file; private state lives under
   `$env:USERPROFILE\.gemini\harness-state\` with its own marker.
8. Native Antigravity surfaces remain `unverified` until a live probe proves them.

## Delivery Phases

### Phase 0 — Truth Reset

- Add capability implementation/availability/enforcement states.
- Reject missing verification references and expired component metadata.
- Reconcile private marker/state semantics and lifecycle hook counts.
- Add a static native-surface probe; keep live-only claims unverified.

### Phase 1 — Bounded Execution

- Add task-contract, job-state, and tool-event schemas.
- Add scope guard, workspace fingerprint, resumable state, and safe command
  evidence helpers.

### Phase 2 — Evidence Closure

- Add test-surface detection, verification envelopes, and fail-closed completion
  arbitration. Source-only evidence remains `checking` until trusted external
  checker attestation exists.
- Preserve real exits, finite timeouts, protected path hashes, and stale-input
  detection.

### Phase 3 — Independent Checking

- Split test author from read-only test runner.
- Keep reviewer read-only and require actual diff/evidence inspection.

### Phase 4 — Behavioral Evals

- Add deterministic regressions for phantom capabilities, scope overreach,
  success-shaped failures, stale verification, zero-test collection, retry
  loops, partial side effects, resume safety, and maker self-approval.

## Completion Gate

The source upgrade is complete only when:

- all new deterministic tests pass;
- package and sync-boundary verification pass;
- the full harness gate passes without installing the real runtime;
- manifests contain no missing paths or unsupported verified claims;
- docs and project context describe observed behavior rather than aspirations;
- remaining live Antigravity-only checks are explicitly reported as unverified.

## v2.1 Follow-Up — Attempt Truth And Tier Routing

Live Canary evidence showed two remaining gaps:

1. the first final report omitted failed attempts until the user requested a
   correction;
2. Tier 0 and the full Tier 1 profile were both injected globally, so the
   claimed on-demand loading did not occur.

v2.1 therefore adds a private, append-only Attempt Ledger and a deterministic
completion-report renderer. Reports must include every failed/rejected attempt,
recovery action, side-effect observation, and `passed_after_retry` status.

The globally loaded `GEMINI.md` becomes a small policy router. The full five
lifecycle policies and Completion Truth guidance move to the
`reliable-maker-control` skill. This reduces global context, but actual
conditional skill loading remains `policy-only / unverified` until a restarted
Antigravity session proves it.

## v2.2 Follow-Up — Observed Evidence

The next live task showed that a model can still self-report line counts,
placeholder input hashes, false `side_effects_observed`, arbitrary evidence
labels, and acceptance criteria not exercised by tests. v2.2 moves these facts
into deterministic observation:

- Task Contracts store a workspace baseline; Scope Guard derives changed paths
  and added lines with `-ObserveWorkspace`.
- Attempt creation derives input and workspace hashes from `-ProjectRoot` and
  `-InputPaths`; attempt closure derives changed paths and side effects.
- Terminal attempts require an existing evidence artifact and store its hash.
- Verification envelopes consume `antigravity-test-result-v1` case results;
  acceptance criteria must match passed case IDs.
- Completion Gate revalidates attempt evidence artifacts and rejects missing,
  changed, or incomplete attempt truth.
- Independent routing evals use fresh Antigravity conversations; same-chat
  prompts are classified as context-contaminated.

## v2.3 Follow-Up — Canonical Execution Provenance

Fresh routing evidence proved the Tier 1 Skill could be discovered, but the
agent manually assembled governance-shaped JSON and claimed canonical scripts
had run. v2.3 requires producer script hashes and a deterministic audit of the
complete contract → ledger → report → structured test result → envelope →
decision chain before any final report may claim governed execution.
