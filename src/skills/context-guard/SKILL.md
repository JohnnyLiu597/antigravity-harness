---
name: context-guard
description: Context budget monitoring, compaction strategies, IAS drift detection, and sub-agent context isolation.
---

# Context Guard

Actively manage context budgets and detect drift before the agent context window reaches limits.

## Compaction Strategies

1. **REACTIVE**: Triggered on immediate `max_output_tokens` or threshold errors. Compacts instantly before retrying the failed operation.
2. **AUTO**: Triggered when context usage exceeds 70%. Executes cleanly before the next API call.
3. **MICRO**: Triggered mid-turn for localized overflow. Removes the oldest non-anchor messages (FIFO) while preserving the last 5 turns.
4. **SCHEDULED**: Triggered every 30 turns. Forces full compaction and anchor verification regardless of current usage.

## Objective Drift Detection

IAS is an advisory self-observation only. It cannot approve completion, expand
scope, select permissions, or force a state transition. Evaluate objective
signals first:

- changed paths versus the task-contract allowlist;
- file, line, dependency, architecture, and side-effect budgets;
- repeated actions without a job-state transition or new evidence;
- unresolved acceptance criteria and stale verification fingerprints;
- whether the recorded next action still advances the objective.

An optional IAS note may summarize subjective alignment:
- **5**: Perfectly aligned, precise progress.
- **4**: Minor deviation, still productive.
- **3**: Drifting, re-explaining context, vague outputs.
- **2**: Off-topic, looping on non-critical tasks.
- **1**: Total loss of original goal.

**Realignment Protocol**: Realign when objective signals show scope drift,
stalled progress, contradictory anchors, or stale state. Re-read the task
contract and job state, restate the goal, and map one next action to an unmet
acceptance criterion. IAS alone never triggers or closes this protocol.

## Compaction Summary Template

When compacting, generate a structured markdown summary to replace historical turns:

```markdown
### Anchor Task
[Verbatim original prompt or goal]

### Completed Steps
1. Configured Windows PowerShell environment.
2. Updated AGENTS.md.

### Active Decisions
- Using `antigravity-harness-schema` due to strict validation requirements.

### Critical Facts
- Target directory: `$env:USERPROFILE\.gemini`

### Next Action
Invoke subagent to verify `GEMINI.md`.
```

## Sub-Agent Isolation Rules

Subagents must be given **minimal context packages**. Do not dump full parent transcripts into `invoke_subagent`. Provide only:
1. The explicit sub-goal.
2. Essential file paths (e.g., `src/components/auth.ts`).
3. Tool allowlist.

## Anchor Re-Read Schedule

- At phase transitions: re-read the active objective, non-goals, and scope.
- Before a write outside the current step: re-read the task contract.
- After compaction or resume: re-read the job state and its one next action.
- Post-Compaction: Always re-read the Compaction Summary.
