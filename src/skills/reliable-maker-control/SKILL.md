---
name: reliable-maker-control
description: Tier 1 policy pack for bounded writes, attempt truth, causal verification, recovery, and maker-checker authority.
---

# Reliable Maker Control — Tier 1 Policy Pack v2.1

This skill is policy-only. Loading it does not prove native hooks, automatic
tool interception, checker identity, or model routing.

## Admission

Use for mission-backed, multi-step, write, delegated, resumed, security,
migration, deployment, publication, or otherwise high-risk work. Record that
the skill was actually read. If it was not read, do not claim Tier 1 active.

## Capability Reality

- Model names and generation settings are preferences, not guarantees.
- `ask_question`, Planning Mode, background task, scheduling, subagent, and
  visualization surfaces require current live evidence.
- Preserve safety requirements when a preferred surface is unavailable.
- Never infer implementation from a manifest, plan, documentation entry, or
  successful-looking wrapper.

## Five Lifecycle Policies

These are model policies, not registered native hooks unless live evidence
proves registration.

### INIT Policy

1. Load the objective and project anchors.
2. Bootstrap one logical task with `new-governed-task.ps1`; reuse its stable
   RegistryRoot, LogicalTaskId, and TaskRoot for retries. A caller-selected new
   ID does not create a new task when the objective and bounded intent match an
   active task. A replacement root requires an explicit prior-root link and
   transition reason.
3. Lock non-goals, allowed/denied paths, change budget, checks, and approvals.
4. Create or resume job state and the private Attempt Ledger.
5. Record native surfaces as observed, unavailable, or unverified.

### PRE_TOOL Policy

1. Start an attempt with `-ProjectRoot` and `-InputPaths` so hashes and the
   workspace-before snapshot are observed by script.
2. Run the caller-declared scope check before mutation. Treat it as
   `pre_write_declared`, not observed enforcement.
3. Request user approval for scope expansion, dependencies, migration,
   destructive effects, merge, deployment, publication, or release.
4. Reconcile uncertain prior effects before retrying.

### POST_TOOL Policy

1. Separate `attempted`, `executed`, and `passed`.
2. Close the attempt with exit and failure class; the script derives workspace
   changes and side effects rather than trusting model self-report.
3. Preserve real exit, timeout, changed paths, and bounded fingerprints.
4. Store safe metadata and hashes only.
5. Run `-ObserveWorkspace` after writes and report it as
   `post_write_observed`; never describe it as a pre-write interception.

### CHECKPOINT Policy

1. Re-read objective, non-goals, scope, remaining checks, blocker, and next action.
2. Compare changed paths, budget, repeated regions, state transitions, failed
   attempts, unresolved blockers, and verification freshness.
3. IAS is advisory and must not decide completion, approval, or permissions.
4. Two identical failures require a changed assumption; three failed
   strategies require `blocked` or user input.

### SHUTDOWN Policy

1. Render the completion report from the Attempt Ledger; do not free-write or
   omit failed/rejected attempts.
2. Reconcile every claim with current evidence and report
   `passed_after_retry` when applicable.
3. Missing or stale evidence is `unverified`.
4. Update approved handoff anchors with outcome, blockers, residual risk, and
   one next action.

## Completion Truth Model

| State | Meaning |
|---|---|
| `planned` | Proposed but not run. |
| `attempted` | Requested; execution unknown. |
| `executed` | Tool returned; correctness unknown. |
| `partial` | Some conditions have evidence. |
| `passed` | One deterministic check passed for recorded inputs. |
| `checking` | Evidence is valid but authority/final checks remain. |
| `unverified` | Evidence is missing, stale, ambiguous, or bound elsewhere. |
| `blocked` | User, authority, environment, or external state is required. |
| `verified` | Current evidence plus trusted external checker attestation. |
| `approved` | User authorized one named high-risk effect; not proof of success. |

Only a completion gate backed by trusted external checker attestation may
assign `verified`. The source-only gate remains `checking`.

## Attempt Truth

- Use the canonical Task Contract, Attempt, Report, Verification Envelope,
  Completion Claim, and Completion Gate scripts. Do not manually assemble
  look-alike JSON artifacts.
- Producer hashes make artifacts deterministically auditable against the
  installed source; they are not cryptographic identity or external authority.
- Before claiming the governed workflow ran, execute
  `audit-governed-execution.ps1` against the task root.
- Every material operation has an attempt ID, operation ID, input hash, status,
  exit, failure class, side-effect flag, recovery action, and evidence path.
- Terminal attempts are immutable; retries create new attempts.
- Every terminal attempt with a ProjectRoot requires valid workspace-before
  and workspace-after fingerprints, even when the initial workspace is empty
  or the operation fails. Failed operations may still have side effects.
- Final reports are rendered by `render-completion-report.ps1`.
- A report that omits or changes a ledger attempt is rejected by the completion
  gate.
- Never describe `passed_after_retry` as a one-shot pass.
- Acceptance criteria must be backed by passed case IDs in an
  `antigravity-test-result-v1` artifact; caller-declared labels alone are not
  coverage evidence.

## Role And Authority Boundaries

- Maker edits only contract-owned product paths and cannot self-verify.
- Test Author edits tests only.
- Test Runner executes declared tests without editing product or test code.
- Reviewer reads the actual diff and evidence but cannot assign `verified`.
- User owns scope expansion, destructive effects, migration, merge,
  deployment, publication, and release.

Self-reported role fields are not trusted identity evidence.

## Source-Backed Claim Truth

- Source fidelity is not external truth. Reopening the same source may verify
  what the source says or shows, but cannot independently prove its factual,
  causal, statistical, legal, financial, or historical claims.
- Record source fidelity and external truth as separate states. Use
  `uncertain` or `not_verified` when independent evidence is absent.
- A supplied path or SHA-256 may establish expected identity; a worker must not
  relabel a copied parent-provided hash as an independently observed hash.
- Claims described as complete, high-confidence, or fully transcribed require
  corresponding artifacts and deterministic checks, not model coverage claims.
- After parser, verifier, and critic stages, produce a Final Claim Set. Final
  summaries, diagrams, core guidance, and cards must derive from that set so
  downgraded or rejected claims do not survive elsewhere in the output.

## Private State And Observability

Private state lives under `$env:USERPROFILE\.gemini\harness-state\`, whose
directory contains a `.gemini-private` marker file. Suggested children are
contracts, jobs, attempt-ledgers, reports, tool-events, verification, evals,
memory, and orchestrator.

Persist only event type, time, repository-relative target, branch, commit,
changed-path count, exit, timeout, retry, duration, state transition, bounded
environment metadata, and hashes. Never persist raw prompts, raw tool input or
output, command payloads, patches, transcripts, secrets, cookies, auth state,
or hidden reasoning.

## Context And Delegation

- Preserve objective, non-goals, decisions, attempt ledger, accepted evidence,
  changed paths, blocker, and one next action.
- Treat chat summaries as hints, not authoritative state.
- Delegate only bounded work with owned paths, dependencies, budget, stop
  condition, evidence contract, and checker identity.
- A worker final message is `executed` at most until outputs and evidence are
  checked.
