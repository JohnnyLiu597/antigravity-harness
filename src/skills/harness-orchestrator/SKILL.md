---
name: harness-orchestrator
description: Bounded maker-checker orchestration using Antigravity native delegation only when live surfaces are available.
---

# Harness Orchestrator

Coordinate native Antigravity work without creating another scheduler, queue, or agent
runtime. Native tool names in this document are policy preferences and remain
runtime-unverified until a current probe supplies evidence.

## Admission

Begin with one execution path. Delegate only when independent work, isolation,
specialization, or checker independence outweighs coordination cost. Before delegation,
lock project identity and define goal, non-goals, owned paths, denied paths, inputs,
dependencies, budget, stop condition, expected output, verification owner, checker, and
join policy.

## Smallest Useful Topology

1. **Serial pipeline** for strict dependencies.
2. **Fan-out/fan-in** for independent branches with one explicit join owner.
3. **Supervisor-workers** for bounded work discovered during execution.
4. **Evaluator-optimizer** only for a measurable revision loop with a hard attempt cap.

## Role Contract

- **Maker** edits only contract-owned paths and must not self-verify.
- **Test Author** edits test files only and cannot approve completion.
- **Test Runner** executes allowlisted checks and must not modify product, source, or test code.
- **Reviewer** reads the actual diff and fresh evidence; it cannot assign `verified`.
- **Parent** integrates accepted outputs and submits evidence to the completion gate.
- **User** retains authority for scope expansion, destructive actions, migrations,
  merge, deployment, publication, and release.

A worker message is `executed` at most. The parent must inspect the actual output; only
the source-only completion gate must remain `checking` even when evidence
matches; only trusted external checker attestation may promote `verified`.

## Native Surface Use

When verified available, use native delegation and message surfaces such as
`invoke_subagent`, `send_message`, `manage_subagents`, `manage_task`, and `schedule`.
If unavailable, report the limitation and keep work serial; do not simulate a second
runtime or use shell polling as an orchestration system.

## Resume and Side Effects

Checkpoint accepted node outputs by hash. Give retries a new attempt ID and preserve a
stable idempotency key only for the same logical side effect. Before retrying an external
write, observe whether the previous attempt already succeeded. Resume from the last
accepted transition instead of rerunning successful siblings.

## Private Records

Store sanitized orchestration state under
`$env:USERPROFILE\.gemini\harness-state\orchestrator\`. The state root contains a
`.gemini-private` marker file. Persist safe metadata and hashes only: role, ownership,
input/output hashes, status, attempt, budget, checker, evidence references, and stop
reason. Never persist a raw prompt, raw tool input, raw tool output, transcript, patch
body, secret, auth state, or hidden reasoning.
