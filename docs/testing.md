# Testing And Evaluation

## v4 current regression entry

`powershell.exe -NoProfile -ExecutionPolicy Bypass -File deploy/test-v4-release.ps1`
owns package verification, bidirectional boundaries and the combined behavioral
runner. v4 case-level owners: test-v4-control, test-v4-policy, test-v4-events,
test-v4-completion, test-v4-knowledge, test-v4-deployment, test-v4-historical-replay
and deploy/test-v4-runtime-sync. Evidence remains under artifacts/v4 and the
existing artifacts/harness-evals/runs. No line/branch coverage has been measured.
The prior 11/11 described suites, not requirements or safety coverage.

The legacy hook test source is retained under tests/fixtures/v351 and is not a v4
assertion owner. Current wrapper/process tests intentionally replace fail-open
malformed input and text-derived exit-code assumptions. Historical fixed Canary
records are replayed only in a new fixture; originals are never rerun.

Native Stop integration, actual new host admission, independent OS actor identity,
real image/video understanding and real vault installation remain pending/blocked,
not passed by deterministic fixtures.

## Verification Ladder

```text
L0  PowerShell parse, JSON/schema validity, formatting
L1  deterministic unit-style script cases
L2  control/verification/governance integration and sync boundaries
L3  isolated runtime startup and persistence probes
L4  live Antigravity canaries for in-app native surfaces
L5  release-critical staging, rollback, behavioral comparison, user review
```

Choose the lowest layer that proves the changed behavior. Missing login, CLI,
quota, desktop state, or live tool access is `blocked`, not passed.

## Deterministic Behavioral Owners

```powershell
.\src\harness-evals\test-truth-reset.ps1
.\src\harness-evals\test-control-plane.ps1
.\src\harness-evals\test-attempt-ledger.ps1
.\src\harness-evals\test-verification-plane.ps1
.\src\harness-evals\test-governance-contracts.ps1
.\src\harness-evals\test-package-integration.ps1
.\src\harness-evals\test-gate-integration.ps1
.\src\harness-evals\run-harness-evals.ps1
```

The suite must prove:

- phantom capabilities and expired component metadata are rejected;
- allowed scope passes and denied/outside/budgeted scope waits for approval;
- job-state transitions are monotonic and evidence-bearing;
- failed and rejected attempts remain present in deterministic
  `passed_after_retry` completion reports;
- Attempt Ledger input hashes, changed paths, side effects, and evidence hashes
  are derived from files rather than model self-report;
- acceptance criteria match passed IDs in structured test-result artifacts;
- independent routing cases use fresh conversations without prior Skill names;
- workspace fingerprints change with source, not ignored artifacts;
- command exits, timeouts, output hashes, and idempotency are preserved;
- nonzero exits cannot be hidden by success-shaped output;
- missing inputs and zero collected tests fail closed;
- source/test/protected changes invalidate verification;
- timed-out process trees cannot produce late side effects;
- makers cannot self-verify;
- an evidence-valid self-reported checker claim remains `checking` until trusted
  external attestation exists.

## Baseline And Candidate Evaluation

Compare v1 and v2 with the same prompt, fixture repository, model policy,
permissions, network policy, timeout, and test surface. Hard safety cases require
binary pass. Track completion rate, pass@1/pass@3, false-completion rate, scope
violations, retries, unnecessary changed-file ratio, evidence freshness,
rollback success, tool calls, duration, and cost per verified task.

Model-based grading is supplementary evidence, never ground truth.
