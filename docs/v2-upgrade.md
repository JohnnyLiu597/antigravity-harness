# Antigravity Harness v2.0 Upgrade Record

## Project Purpose

`antigravity-harness` is a Windows-first reliability control plane for Google
Antigravity and Gemini CLI. It does not replace the native runtime or claim to
improve the underlying model. It constrains scope and side effects, persists
recoverable state, validates current evidence, separates maker/checker roles,
and keeps merge, deployment, publication, migration, and destructive authority
with the user.

The design goal is not "the agent never fails". The goal is that failures are
visible, bounded, recoverable, and cannot be converted into unsupported
completion claims.

## v2.0 Changes

- Replaced aspirational capability claims with implementation, availability,
  enforcement, evidence, and component-lifecycle truth registries.
- Added task contracts with objective, non-goals, allowed/denied paths, file and
  line budgets, dependency/architecture policy, required checks, and approval
  triggers.
- Added monotonic resumable job state, optimistic version checks, attempts,
  blockers, one next action, workspace fingerprints, and evidence references.
- Added bounded command execution with real exits, finite timeouts, output
  hashes, operation identity, idempotency indexes, and uncertain-side-effect
  retry blocking.
- Added causal verification envelopes for source, tests, protected paths,
  workspace state, test collection, timeout cleanup, and detached hashes.
- Bound claimed test execution to actual PowerShell command AST invocation of a
  declared test path; printing a path and fake test count is rejected.
- Added acceptance-criterion coverage binding so claims cannot introduce
  business conditions that the envelope did not check.
- Added fail-closed completion arbitration. Because project-local JSON cannot
  prove reviewer identity, deterministic evidence ends in `checking`; only a
  future trusted external attestation may issue `verified`.
- Split Maker, Test Author, Test Runner, Reviewer, and Human Approver authority.
- Made IAS advisory and replaced it with objective scope, progress, state,
  fingerprint, and evidence signals.
- Standardized `.gemini-private` as a marker file and
  `$env:USERPROFILE\.gemini\harness-state\` as the private state root.
- Added Windows long/8.3 path normalization and shorter atomic temp filenames.
- Added deterministic truth, control, verification, governance, package, gate,
  scaffold, and sync-boundary regressions.
- Extended runtime sync to include `schemas/` and `harness-evals/` while
  excluding generated eval runs and `harness-state/` at every depth.

## Evidence Status

- Source behavioral evals: passed.
- Package and leak scan: passed.
- Bidirectional sync-boundary integration: passed.
- Full source verification gate: passed.
- Real runtime installation: completed transactionally on 2026-09-04.
- Live in-app Antigravity tools, model routing, lifecycle interception, and
  trusted checker attestation: unverified and intentionally not overstated.

## Runtime Installation

Observed installation evidence:

```text
status: installed
transaction_id: d50301e38968405aabb484bee8d6aefd
source_file_count: 52
installed_file_count: 52
source_fingerprint: fe2d587d823f9bf531163f63161046f51c5bd783684f4997ecd15d5462622088
hash_mismatches: 0
rollback: not-needed
```

Recoverable backup and transaction manifest:

```text
$env:USERPROFILE\.gemini\backup-20260904-222432-aaf34979-antigravity-harness-sync\
$env:USERPROFILE\.gemini\backup-20260904-222432-aaf34979-antigravity-harness-sync\sync-transaction.json
```

Post-install checks executed through the installed runtime scripts:

- manifest integrity: passed;
- 52 transaction target hashes: passed with zero mismatches;
- core source/runtime hashes: matched;
- full verification gate: passed;
- rollback: not needed.

The static runtime probe still reports the in-app Antigravity surfaces, model
routing, and trusted checker attestation as `unverified`. Installation does not
convert those claims into live evidence.

## v2.1 Attempt Truth And Tier Routing

The first live Canary proved the installed scripts worked but also exposed two
remaining problems: the initial final report hid failed attempts, and both Tier
0 and the full Tier 1 profile were globally injected.

v2.1 adds an append-only private Attempt Ledger, immutable terminal attempts,
failure/recovery/side-effect fields, deterministic `passed_after_retry`
reporting, and completion-gate comparison against the original ledger.

The full policy pack moved from global `GEMINI.md` to
`skills/reliable-maker-control/SKILL.md`. The new global router is intentionally
small. A restarted live canary is still required before conditional skill
loading may be considered observed.

See `docs/live-canary-20260904.md` for the sanitized Canary evidence and the
failure that motivated this upgrade.

Observed v2.1 installation evidence:

```text
status: installed
transaction_id: 91cf76e6e78d42d4bb539690808ab922
source_file_count: 58
installed_file_count: 58
source_fingerprint: a167633aa536c3a2df94d2da18697d55366fe34047a25f8063dea82715acbd80
hash_mismatches: 0
rollback: not-needed
```

Latest rollback point:

```text
$env:USERPROFILE\.gemini\backup-20260904-234514-0ccd2ed8-antigravity-harness-sync\sync-transaction.json
```

The installed verification gate passed after the v2.1 transaction. Runtime
installation proves file deployment and deterministic source behavior; it does
not yet prove that Antigravity conditionally reads the Tier 1 skill.

## v2.2 Observed Evidence Upgrade

A subsequent task exposed remaining self-report weaknesses: Scope Guard used a
caller-provided line count, Attempt Ledger used placeholder input hashes and
reported false for observed file-write side effects, an evidence field accepted
free text, and an untested `links-valid` criterion entered the envelope.

v2.2 adds contract baseline snapshots, observed scope deltas, script-derived
attempt input/workspace hashes, automatic side-effect detection, required
evidence files with hashes, structured named test cases, acceptance-criterion
binding, and Completion Gate evidence revalidation.

The same task also contained mojibake and an incorrect `.gemini-private`
description that shallow keyword tests missed. `tests/getting-started.tests.ps1`
now checks encoding, marker semantics, referenced script paths, required v2.2
arguments, and emits `antigravity-test-result-v1`.

Routing experiments performed in one conversation are context-contaminated.
See `docs/evaluation-protocol.md` for the fresh-conversation rule.

## v2.3 Execution Provenance

A fresh-conversation Canary successfully discovered the Tier 1 Skill but then
manually assembled an Attempt Ledger and completion report. It created no Task
Contract, Verification Envelope, Completion Claim, or Completion Decision, yet
its natural-language summary claimed that the full gate ran and returned
`checking`.

v2.3 adds canonical producer script hashes to contracts, ledgers, updates, and
reports, rechecks those hashes in the Completion Gate, and adds
`audit-governed-execution.ps1`. The audit requires a private marker, contract,
ledger, completion report, structured test result, passed verification envelope,
and checking/verified decision. The mechanism is tamper-evident source
provenance, not a cryptographic external identity guarantee.

Observed v2.3 installation evidence:

```text
status: installed
transaction_id: 9f1d26cab1f44364b4453a6508eafee8
source_file_count: 60
installed_file_count: 60
source_fingerprint: b6da914bfaeeda070bd674054fde292f608a0a9a9b2a46264feee8dddbac3d8c
hash_mismatches: 0
rollback: not-needed
```

Latest rollback point:

```text
$env:USERPROFILE\.gemini\backup-20260905-190125-bb4c8cd1-antigravity-harness-sync\sync-transaction.json
```

Observed v2.2 installation evidence:

```text
status: installed
transaction_id: 451216d2906a49d3988fe1b0593fb07a
source_file_count: 58
installed_file_count: 58
source_fingerprint: 3048737bdce91b43598d1424660443d07dead072003e84dc570ab931a8c20324
hash_mismatches: 0
rollback: not-needed
```

Latest rollback point:

```text
$env:USERPROFILE\.gemini\backup-20260905-183505-a1c35505-antigravity-harness-sync\sync-transaction.json
```
## v2.4 TaskRoot Continuity And Canonical Claims

The fresh-window v2.3 Canary proved most of the governed chain but exposed an
empty-workspace serialization defect and a way to abandon one TaskRoot and
restart the same logical task without carrying its failed attempts forward.
It also showed that post-write scope observation could be mistaken for a
pre-write guard and that Completion Claim JSON was still manually assembled.

v2.4 adds:

- canonical empty-array baseline hashing in `new-task-contract.ps1`;
- `new-governed-task.ps1`, with one active registered TaskRoot per logical task
  and explicit prior-root transitions;
- explicit `pre_write_declared` and `post_write_observed` scope modes;
- `new-completion-claim.ps1` and claim producer checks in the completion gate
  and governed-execution audit;
- deterministic regression cases for all four behaviors.

Producer hashes are intentionally documented as source-version audit metadata.
They do not establish an unforgeable runtime identity and cannot promote a
source-only result beyond `checking`.

Observed v2.4 installation evidence:

```text
status: installed
transaction_id: 3a9839cf940746ff8ea6a3c53f095662
source_file_count: 62
installed_file_count: 62
source_fingerprint: 47da670d83b7388cbf1fb81db6f8052eb5bdc94e4bbf6b509d8c94e73c6238a6
hash_mismatches: 0
behavioral_evals: 10/10 passed
installed_gate: passed
rollback: not-needed
```

Latest rollback point:

```text
$env:USERPROFILE\.gemini\backup-20260905-233655-9cf2a6a2-antigravity-harness-sync\sync-transaction.json
```
## v2.5 Failed-Side-Effect Closure

The v2.4 full-chain Canary exposed an empty-snapshot truthiness defect in
`update-attempt-record.ps1`. A failed Attempt created its test file but recorded
no workspace-after fingerprint, no changed path, and no side effect.

v2.5:

- serializes empty Attempt snapshots as the canonical JSON array `[]`;
- always computes the after snapshot for ProjectRoot-backed terminal Attempts;
- records side effects for failed operations instead of equating failure with
  no mutation;
- rejects terminal Attempt observations that lack valid before/after hashes,
  have changed fingerprints without paths, or have paths while claiming no
  side effects;
- adds RED/GREEN regressions at both the Attempt Ledger and Completion Gate.

The same Canary was prompt-directed to load the Tier 1 Skill. It does not prove
autonomous Skill routing, even though the Skill was successfully read.

Observed v2.5 installation evidence:

```text
status: installed
transaction_id: 664ae1ed944644ef99feef8de6fc0337
source_file_count: 62
installed_file_count: 62
source_fingerprint: 6f3f5f7b136639a3dae57c6c8fd0715059cc72fd0b52320138843a4936a29551
hash_mismatches: 0
behavioral_evals: 10/10 passed
installed_gate: passed
rollback: not-needed
```

Latest rollback point:

```text
$env:USERPROFILE\.gemini\backup-20260906-005116-ef404153-antigravity-harness-sync\sync-transaction.json
```
## v2.6 Task-Intent Continuity

The v2.5 Canary passed its inner governed workflow but omitted two earlier
governed roots created by failed wrapper executions. Each retry generated a new
timestamped LogicalTaskId and RegistryRoot, so ID-based continuity could not
recognize the same underlying task.

v2.6:

- normalizes objective, non-goals, allowed and denied paths, required checks,
  and budgets into `task_intent_sha256`;
- indexes active intent separately from caller-selected LogicalTaskId;
- rejects an equivalent active intent under a renamed ID with
  `task_intent_already_active` and returns the resumable LogicalTaskId;
- writes `.gemini-private` into RegistryRoot;
- records the intent hash in TaskRoot manifest and requires it in provenance
  audit;
- adds RED/GREEN regressions for cross-ID intent escape.

This controls retries only when they use the same RegistryRoot and invoke the
governed bootstrap. A host-level failure before bootstrap remains outside the
PowerShell control plane.

Observed v2.6 installation evidence:

```text
status: installed
transaction_id: 34c0ebb987374d21ae084283333e69ee
source_file_count: 62
installed_file_count: 62
source_fingerprint: f1bb07780e6be91cf55717d924b78c579d5f03681be0a5c69aca48594d3ae5be
hash_mismatches: 0
behavioral_evals: 10/10 passed
installed_gate: passed
rollback: not-needed
```

Latest rollback point:

```text
$env:USERPROFILE\.gemini\backup-20260906-010941-47b645d8-antigravity-harness-sync\sync-transaction.json
```
