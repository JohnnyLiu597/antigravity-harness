---
name: trajectory-capture
description: Privacy-safe observable action metadata for reliability analysis without prompts, payloads, transcripts, or reasoning traces.
---

# Trajectory Capture

Capture bounded observable events for debugging and evaluation. This is not a hidden
reasoning recorder and does not prove that a task is complete.

## Storage

Write runtime-private records under
`$env:USERPROFILE\.gemini\harness-state\trajectories\`. The state root contains a
`.gemini-private` marker file. The marker only protects the directory boundary; it is
not a state directory itself.

## Safe Event Schema

Each JSONL event may contain safe metadata and hashes only:

```json
{
  "session_ref_hash": "sha256",
  "task_ref_hash": "sha256",
  "attempt_ref_hash": "sha256",
  "timestamp": "iso8601",
  "phase": "planned | attempted | executed | checking | blocked",
  "event_type": "tool | edit | check | approval | checkpoint",
  "tool_class": "string",
  "operation_ref_hash": "sha256",
  "input_hash": "sha256",
  "output_hash": "sha256",
  "workspace_fingerprint": "sha256",
  "changed_path_count": 0,
  "exit_code": 0,
  "timed_out": false,
  "retry_count": 0,
  "duration_ms": 0,
  "state_transition": "attempted -> executed",
  "ias_advisory": 0
}
```

IAS is an advisory self-observation only. It is not dataset eligibility, a drift gate,
or completion evidence.

## Privacy Boundary

Never persist a raw prompt, raw tool input, raw tool output, command payload, patch body,
assistant message, transcript, secret, credential, cookie, auth state, or hidden
reasoning. Repository-relative paths are allowed only when they are non-sensitive;
otherwise store hashes. Do not copy environment-variable values.
Never persist hidden reasoning or an inferred chain of thought in any trajectory record.

## Session Summary

Summaries may contain objective hash, accepted state transitions, changed path count,
verification references, failure classifications, retry counts, durations, blockers,
and the unique next action. Claims remain `unverified` until the completion gate accepts
fresh evidence bound to the current source state.

## Evaluation Eligibility

A trajectory may be considered for sanitized reliability analysis only when its source
and consent policy allows it, privacy checks pass, and deterministic evidence is linked.
Never treat low retry count, high IAS, model agreement, or a fluent summary as proof of
correctness.
