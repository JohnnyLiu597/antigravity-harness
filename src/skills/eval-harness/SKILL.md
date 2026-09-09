---
name: eval-harness
description: Deterministic, evidence-bound behavioral evaluation with model judgment limited to non-deterministic criteria.
---

# Evaluation Harness

Evaluate Antigravity roles, tools, and workflows against observable outcomes. The skill
definition is policy-only until an implemented runner executes real cases.

## Evaluation Workflow

1. State the claim, risk, baseline, candidate, and observable pass condition.
2. Select the smallest known-regression, normal, and boundary cases that can falsify it.
3. Run deterministic checks first with finite timeouts and real exit codes.
4. Bind evidence to source, test, grader, configuration, environment, and protected-path
   fingerprints.
5. Use a model judge only for criteria that cannot be made deterministic. Its score is
   advisory and cannot assign `verified`.
6. Return Keep, Revise, or Reject with residual uncertainty and evidence references.

## Required Reliability Cases

Include cases for phantom capability, scope overreach, success-shaped failure, zero
tests collected, stale verification, deterministic retry loops, uncertain side effects,
compaction resume, Maker self-approval, destructive actions, and quota degradation.

## Hard Gates

- Nonzero child exit codes fail even when output contains successful JSON.
- Missing required inputs or evidence fail.
- Source, test, grader, configuration, or protected-path changes invalidate old evidence.
- High-risk behavior requires 100% deterministic safety cases and explicit user authority.
- Model agreement, self-score, and fluent summaries are never reality anchors.

## Storage and Privacy

Store sanitized results under `$env:USERPROFILE\.gemini\harness-state\evals\`; the
state root contains a `.gemini-private` marker file. Records contain safe metadata and
hashes only. Never persist a raw prompt, raw tool input, raw tool output, transcript,
patch body, secret, auth state, or hidden reasoning.

The completion gate, not this skill or its judge, decides whether all required evidence
supports `verified` for the current source state.
