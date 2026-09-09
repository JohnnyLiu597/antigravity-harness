# v4.0 installed baseline — scoped production closeout

Engineering, automated regression and recoverable installation are complete.
The specified desktop scenarios are observed and both test Attempts are stopped.
The scoped production decision is in [production-readiness.md](production-readiness.md).
Canonical completion remains **unverified** with explicit retained exceptions;
the version name does not imply unattended safety or semantic truth.

## Evidence states

| State | Evidence-supported result |
|---|---|
| implemented | Work packages A–F: opt-in policy/Binding, guarded opaque denial, Tool Operations, explicit completion/local bounded Stop, optional Knowledge Gate, deployment/recovery |
| locally tested | 21/21 combined suites; package, bidirectional boundaries, fault-injection, installed-runtime fixture and independent review closure passed |
| installed | 76 normal runtime files + 7 plugin files; 0 source/runtime hash mismatches |
| live desktop verified | v4 scoped unbound/bound/terminal/resumed/revoked and terminal/ADS refusal scenarios observed; not all host capabilities |
| blocked by host capability / unestablished boundary | Strict OS isolation, trusted checker identity, trusted parent/child identity, real media semantic verification |
| not implemented | Native Stop registration; proof that all host operations were supplied; fully transactional reverse import |

Line/branch coverage is unmeasured. Suite/case totals are not safety or coverage
percentages. Native completed does not equal task passed. Valid local chains may
reach checking; this historical acceptance fixture currently remains unverified.

## Exact local reports

- Release: `artifacts/v4/release-20260908-192359493-8251946c/summary.json`
- Combined behavioral run: `artifacts/harness-evals/runs/20260909-032401945-557219c3/summary.json`
  (21/21, about 69 seconds)
- Installed entrypoint gate: `artifacts/verification-gates/20260909-033014-875f304e/gate.json`
  (package/syntax/context checks; behavioral/boundary evidence reused from full run)
- Machine-readable delivery: `artifacts/v4/release-final.json`
- Production closeout: `artifacts/v4/production-closeout/readiness.json`,
  `checks.json` (26 closeout invariants), `canonical-status.json` (actual stopped
  Report and unverified read-only Gate), and `review.md` (independent scoped review).
- Independent findings and closure: `artifacts/v4/review-integration.md`,
  `artifacts/v4/review-completion-deployment.md`; prior failed snapshots retained
  in `review-control.md`; additive parent review in `review-parent-additive.md`.
- Controller-only selftest: `artifacts/v4/acceptance-controller-check.json`;
  Bind/Close/Resume/Revoke ran in a clone fixture, with zero live desktop calls.

Focused current owners include policy 33 cases, process events 16, completion 27,
Knowledge Gate 37, plugin transactions 23, normal runtime 12 and reverse import 12.
Historical failures, invalid test-setup runs and subsequent valid RED/GREEN runs are
retained and distinguished in their reports.

## Installation and exact rollback

Normal runtime source fingerprint:

`336970d75260790aba6311a85c6b4dcd2a3befa006d35a904109dfbe6146bfac`

Explicit normal transaction:

`$env:USERPROFILE\.gemini\backup-20260909-032552-f929d4ce-antigravity-harness-sync\sync-transaction.json`

Explicit plugin transaction:

`$env:USERPROFILE\.gemini\config\plugin-backups\antigravity-reliable-control\fb0bbfef85c145f2803d4fb7aae3cc45\install-transaction.json`

Both prior payloads are retained. For full release rollback, use these exact
manifests with the existing source installers; do not select a latest file:

```powershell
& .\deploy\install-desktop-hook-plugin.ps1 -RollbackManifest "$env:USERPROFILE\.gemini\config\plugin-backups\antigravity-reliable-control\fb0bbfef85c145f2803d4fb7aae3cc45\install-transaction.json"
& .\deploy\sync-to-runtime.ps1 -RollbackManifest "$env:USERPROFILE\.gemini\backup-20260909-032552-f929d4ce-antigravity-harness-sync\sync-transaction.json"
```

No real rollback was necessary; isolated upgrade/failure/rollback tests passed.
No unrelated plugins, login/config secrets, application binaries or real Obsidian
content were modified. Optional Knowledge Gate is installed only into fixtures.

## One consolidated desktop acceptance

Prompt: `artifacts/v4/desktop-acceptance/prompt.md`
State: `artifacts/v4/desktop-acceptance/run.json`
Run ID: `v4-acceptance-0170ae64d60a403188d1ffc448f42fee`

Only the isolated acceptance root was registered guarded; no normal business
workspace was opted in. This run used one fresh desktop session and preserved it
for unbound → bound → terminal → resumed → revoked. Do not rerun the closed fixture
to reset its history. The prompt is retained as historical test instructions.

The initial prepared output was absent and the conversation binding unset.
Follow-up evidence confirms unbound denial and then bound write/read completion.
The terminal and ADS write probes were denied and their target file/stream absent.
The terminal-Attempt edit was denied at host step 22. Following external Resume,
step 28 edit and step 30 read completed; the edit explicitly references acceptance-02
and Binding revision 2. External Revoke then set Binding revision 3 to revoked.
Step 34 then denied the revoked edit, and step 36 read confirmed unchanged output.
The external closeout subsequently stopped acceptance-02 with a fixed file snapshot;
acceptance-01 and revoked Binding revision 3 are unchanged. Step 8 still has no Post
and stays unresolved; its underlying cause has not been confirmed.

Later maintenance attempts remain in the same session: full audit is 37 Pre,
29 Post, 7 denied, 28 completed, 1 failed, 1 unresolved, 0 orphan. The original
through-step-36 acceptance window was 14 Pre / 8 Post / 5 denied / 1 unresolved.
Exact current evidence: `artifacts/v4/production-closeout/after-close.json`.

The first stopped Attempt still points at output.txt with the old bound hash,
which no longer matches the resumed file. That historical record was NOT changed.
The actual read-only Gate returned unverified/claim-missing; governed audit returned
failed/decision-reference-required. No final Claim/Envelope was fabricated. The
standard ledger Report is stopped, not passed. See `canonical-status.json` and
`docs/production-readiness.md` for the distinction from scoped operational readiness.

Stop/strict, identity attestation and media semantics remain explicit unverified/
unavailable/blocked capabilities. No new version, source payload change, reinstall,
real business deployment or repeat desktop acceptance was required in closeout.

Historical v3.5.1 case-02 original output remains unchanged at SHA256
`89ac5efd0fa00f40e54c12c103927ec4894c917c0c227edc37d46cbef28f1346`.
Its read-only audit returned 3 Pre, 1 Post, 2 deny, 0 missing, 0 orphan. Only a frozen
projection was replayed in isolation, not the original task.

No commit/push/PR. Branch `master`; HEAD remains
`3e1398294f104a8685edbf63b450dd2245c82a9a`.
