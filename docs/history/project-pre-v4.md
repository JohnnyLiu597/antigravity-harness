# Historical pre-v4 snapshot; superseded by current docs/project.md.

# Project Onboarding And Adoption

## Context Anchors

Target repositories use neutral shared anchors:

```text
mission.md
CONTEXT.md
.agent/rules.md
MEMORY.md
README.md
```

`AGENTS.md` and `GEMINI.md` contain engine-specific policy. A target project
may use Codex and Antigravity together while their physical runtimes remain
separate.

## Scaffolding

```powershell
.\src\scripts\init-project-harness.ps1 `
  -Root "C:\path\to\target-repo" `
  -ProjectName "MyTarget"
```

The scaffold creates project anchors and `.agent/rules.md`. Non-trivial work
then starts with `new-governed-task.ps1`, which creates the private task
contract, TaskRoot identity, and continuity registry before attempts begin.

## Adoption Levels

### Level 0 — Read Only

The agent inspects project identity and reports uncertainty. No scaffold,
delegation, or write occurs before identity is locked.

### Level 1 — Bounded Single Agent

The project has anchors, a task contract, path scope, change budget, and a
minimal verification command.

### Level 2 — Evidence Closed

Workspace fingerprints, safe command evidence, verification envelopes, and the
completion gate are active. `verified` cannot be self-issued.

### Level 3 — Maker-Checker

Medium/high-risk work uses isolated Maker, Test Runner, and Reviewer roles.
Deployment, migration, publication, and destructive effects remain user-owned.

### Level 4 — Resumable Orchestration

Only after Level 3 is reliable may the project use background, scheduled,
multi-agent, or resumed work with budgets, idempotency, durable state, join
rules, and conservative stop conditions.

## Definition Of Done

No task is complete until all required claims have current evidence, trusted
checker authority promotes the source gate's `checking` result to `verified`,
residual uncertainty is reported, and any required high-risk approval is
supplied by the user. Until attestation exists, report the task as checking.
