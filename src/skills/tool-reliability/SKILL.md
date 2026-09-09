---
name: tool-reliability
description: Evidence-bound tool failure classification, side-effect checks, bounded retries, and loop prevention.
---

# Tool Reliability

Use observable state to make tool recovery safe. This skill is a policy-only procedure
unless a current runtime probe and verification script provide enforcement evidence.

## Failure Workflow

1. **Observe**: Capture safe metadata and hashes: tool class, operation ID hash, target
   path hash or repository-relative path, start/end time, real exit code, timeout flag,
   retry count, and bounded before/after state fingerprints.
2. **Classify**: Choose exactly one primary category.
3. **Check effects**: Before retrying, determine whether the previous attempt changed
   the target or completed its external side effect.
4. **Change one assumption**: Use a new attempt ID while keeping the idempotency key
   stable for the same logical side effect.
5. **Record**: Store the sanitized failure event under
   `$env:USERPROFILE\.gemini\harness-state\failures\`. The state root contains a
   `.gemini-private` marker file; the marker itself is never a directory.

## Failure Categories

- `task-caused`: the current change introduced the failure.
- `pre-existing`: the same failure exists without the current change.
- `environment`: a runtime, dependency, path, service, or quota condition blocks work.
- `permission`: required authority is absent.
- `timeout`: the operation exceeded its finite budget and final effect is not yet known.
- `tool-defect`: the tool or wrapper failed independently of the requested operation.
- `assumption-error`: the observed state disproves an execution assumption.
- `insufficient-evidence`: available observations cannot distinguish the cause.

## Retry Contract

- Use at most three total attempts for one logical operation.
- Identical input and identical deterministic error on the second observation stops
  blind retry immediately.
- Re-observe current state before every retry; a timeout is not proof of no side effect.
- Change exactly one falsifiable variable per retry and record which variable changed.
- After three failed attempts, transition to `blocked` or request user input.
- Never retry deployment, publication, release, migration, deletion, payment, or other
  external writes until current state proves that repetition is safe and the user has
  approved the operation.

## Truth and Privacy

`attempted` means a call was requested. `executed` means the tool returned. Neither
means `passed` or `verified`. Success-shaped output never overrides a nonzero exit code,
a timeout, stale fingerprints, or missing evidence.

Failure records contain safe metadata and hashes only. Never persist a raw prompt, raw
tool input, raw tool output, patch body, transcript, credential, cookie, auth state,
secret, or hidden reasoning. Store output digests and bounded classifications instead.
