# Architecture — Antigravity Desktop v4

## Product and three boundaries

Source is src/ in this repository. Normal runtime payload installs into .gemini;
the existing Desktop plugin installs into config/plugins/antigravity-reliable-control.
Private operational state remains under harness-state with .gemini-private.
The marker controls sync exclusion; it is not a filesystem permission.

No configuration is borrowed from another agent engine. Desktop, IDE, CLI and SDK
interfaces are not assumed equivalent. Application binaries and unrelated plugins
are outside scope. Optional knowledge adapters stay separate from global runtime.

## Authorization path

Host PreToolUse supplies conversation identity, step index and tool arguments.
The existing plugin calls one shared control-lib.ps1 to:

1. classify explicit project policy, default observe;
2. reject invalid/control-plane targets and unavailable strict mode;
3. deny opaque terminal/subagent execution associated with guarded projects;
4. validate current Binding, Contract, TaskRoot, running Attempt, role and scope;
5. write the effective admission into a locked, flushed Tool Operation record.

Binding has revision, expiry, revoke, prior Attempt reference and narrowing-only
renewal. Contract access/status, identity and hash are rechecked. Alias checks cover
relative/case paths, ADS/device paths, ancestor reparse points and file link counts.
Windows handle checks do not eliminate the race between hook response and host write.
Existing same-user agents can tamper outside these observed tools. Strict is unavailable.

## Tool Operation ledger

Operation identity derives from host conversation hash plus step index, not model
tool names or claimed parentage. Each operation contains a typed allowlisted callback
history, hashes linking Task/Attempt, and separate requested/child/host code slots.
Post adds an observation without closing Task Attempt. Command result text is never
parsed as trusted process proof. Missing Post = unresolved; malformed/unknown/opaque
Post = unclassified. completed is native tool observation, not accepted business work.

Exclusive per-operation file handles coordinate writes. Temp+flush+atomic replacement
preserve previous versions. Duplicate Pre records a deny; identical Post is idempotent;
out-of-order and conflicting results remain explicit. This is local recoverable
logical history, not append-only tamperproof storage. Empty, bad-shape, corrupt and
pending records are surfaced by a read-only transcript-free audit.

## Completion and knowledge

Canonical Contract, Ledger, Report, Claim, Envelope and structured test records must
be connected by explicit references and current hashes, never independent newest-file
selection. Source-only Gate may establish checking, not trusted external verified.
Role strings, producer hashes and a second model opinion do not attest authority.
The bounded Stop evaluator has finite follow-ups and cancel/disable precedence;
native host Stop registration is not claimed.

The optional Knowledge Gate separates original fidelity from external truth, independently
hashes files, validates duration/transcript constraints and requires one Final Claim Set
for canonical body/card/diagram output. Semantic/model identity remains unverified;
native media unavailability blocks completion. Real Obsidian is not modified.

## Recovery and deployment

Normal runtime and plugin have separate explicit transactions: stage, validate, switch,
postcheck, retain backup/failure, explicit manifest rollback. Plugin directory switch is
not a single atomic two-directory swap; normal runtime per-file swaps do not make an
entire release atomic. Interrupted journals block subsequent installs until recovery.
No automatic retention deletion; capacity, timeout and recovery limits are in
docs/v4-operations.md and docs/v4-deployment.md.

Current source/test/install/live distinctions: docs/v4-release.md.
Historical architecture and runtime canaries remain in versioned docs/v3-*.md and
docs/live-*.md; they are not blanket v4 capability declarations.
# 2026-09-10 asymmetric adapter

The shared protocol lives at project scope; the native Antigravity governance
remains the acceptance authority. `invoke-antigravity-handoff.ps1` hardcodes the
producer, matches the native logical task ID and invokes the original fresh audit
before Handoff. Shared status never becomes verified. All native strong hashes,
required checks, guarded restrictions and historical failures remain unchanged.
The common script/schema have reviewed identical copies in both harness packages.
See [collaboration](agent-collaboration.md).
